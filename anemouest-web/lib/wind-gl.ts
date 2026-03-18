// WindGL — Mapbox Custom Layer for animated wind visualization
// Renders a colored heatmap + animated particles using FBO ping-pong fade (nullschool style)
// Uses MercatorCoordinate for projection → works in both globe and mercator modes

import mapboxgl from 'mapbox-gl'

// ===== Color Scale (knots) =====
// Exported so legend can use the same scale
export const COLOR_STOPS_KTS: [number, number, number, number][] = [
  [0, 98, 113, 183],
  [3, 57, 136, 210],
  [5, 30, 172, 230],
  [8, 30, 205, 180],
  [11, 55, 210, 100],
  [14, 115, 220, 50],
  [16, 200, 225, 30],
  [19, 245, 200, 30],
  [22, 250, 150, 25],
  [24, 245, 100, 20],
  [27, 235, 50, 35],
  [30, 220, 30, 75],
  [32, 200, 30, 145],
  [38, 175, 50, 200],
  [43, 150, 80, 225],
  [54, 180, 120, 255],
  [65, 210, 170, 255],
]

const MAX_SPEED_KTS = 65 // max of color scale

function speedToColor(kts: number): [number, number, number] {
  if (kts <= COLOR_STOPS_KTS[0][0]) return [COLOR_STOPS_KTS[0][1], COLOR_STOPS_KTS[0][2], COLOR_STOPS_KTS[0][3]]
  for (let i = 1; i < COLOR_STOPS_KTS.length; i++) {
    if (kts <= COLOR_STOPS_KTS[i][0]) {
      const [k0, r0, g0, b0] = COLOR_STOPS_KTS[i - 1]
      const [k1, r1, g1, b1] = COLOR_STOPS_KTS[i]
      const t = (kts - k0) / (k1 - k0)
      return [
        Math.round(r0 + t * (r1 - r0)),
        Math.round(g0 + t * (g1 - g0)),
        Math.round(b0 + t * (b1 - b0)),
      ]
    }
  }
  const last = COLOR_STOPS_KTS[COLOR_STOPS_KTS.length - 1]
  return [last[1], last[2], last[3]]
}

// Build a 256x1 color ramp texture data (shared between heatmap and particles)
function buildColorRamp(): Uint8Array {
  const data = new Uint8Array(256 * 4)
  for (let i = 0; i < 256; i++) {
    const kts = (i / 255) * MAX_SPEED_KTS
    const [r, g, b] = speedToColor(kts)
    data[i * 4] = r
    data[i * 4 + 1] = g
    data[i * 4 + 2] = b
    data[i * 4 + 3] = 255
  }
  return data
}

// km/h to knots conversion
const KMH_TO_KTS = 0.539957

// ===== Shader Sources =====

const HEATMAP_VS = `
attribute vec2 a_pos;
attribute vec2 a_texcoord;
uniform mat4 u_matrix;
varying vec2 v_texcoord;
void main() {
  gl_Position = u_matrix * vec4(a_pos, 0.0, 1.0);
  v_texcoord = a_texcoord;
}
`

const HEATMAP_FS = `
precision mediump float;
uniform sampler2D u_texture;
uniform float u_opacity;
varying vec2 v_texcoord;
void main() {
  vec4 color = texture2D(u_texture, v_texcoord);
  gl_FragColor = vec4(color.rgb, color.a * u_opacity);
}
`

// Particle shader: draws GL_POINTS into the FBO, colored by wind speed
const PARTICLE_VS = `
attribute vec2 a_pos;
attribute float a_speed;
uniform mat4 u_matrix;
uniform float u_pointSize;
varying float v_speed;
void main() {
  gl_Position = u_matrix * vec4(a_pos, 0.0, 1.0);
  gl_PointSize = u_pointSize;
  v_speed = a_speed;
}
`

const PARTICLE_FS = `
precision mediump float;
uniform sampler2D u_colorRamp;
uniform float u_alpha;
uniform float u_useColor;
uniform vec4 u_fallbackColor;
varying float v_speed;
void main() {
  float d = length(gl_PointCoord - 0.5) * 2.0;
  if (d > 1.0) discard;
  vec4 rampColor = texture2D(u_colorRamp, vec2(v_speed, 0.5));
  vec4 color = mix(u_fallbackColor, vec4(rampColor.rgb, 1.0), u_useColor);
  gl_FragColor = vec4(color.rgb, u_alpha * (1.0 - d * 0.3));
}
`

// Screen-space quad shader: used for both FBO fade pass and final compositing
const SCREEN_VS = `
attribute vec2 a_pos;
varying vec2 v_uv;
void main() {
  v_uv = a_pos * 0.5 + 0.5;
  gl_Position = vec4(a_pos, 0.0, 1.0);
}
`

// Fade shader: multiply RGB by fade factor, keep alpha=1 (FBO is opaque internally)
// floor trick prevents floating-point accumulation (values that never reach 0)
const FADE_FS_FIXED = `
precision mediump float;
varying vec2 v_uv;
uniform sampler2D u_texture;
uniform float u_fade;
void main() {
  vec4 c = texture2D(u_texture, v_uv);
  gl_FragColor = vec4(floor(c.rgb * u_fade * 255.0) / 255.0, 1.0);
}
`

// Screen composite shader: output RGB only, alpha=0 (additive blend ignores alpha)
const SCREEN_FS = `
precision mediump float;
varying vec2 v_uv;
uniform sampler2D u_texture;
uniform float u_opacity;
void main() {
  vec4 c = texture2D(u_texture, v_uv);
  gl_FragColor = vec4(c.rgb * u_opacity, 0.0);
}
`

// ===== Wind Data Interface =====

export interface WindData {
  u: number[]
  v: number[]
  speeds: number[]
  pressure?: (number | null)[]
  width: number
  height: number
  bounds: { latMin: number; latMax: number; lonMin: number; lonMax: number }
}

// ===== Helpers =====

function createShader(gl: WebGLRenderingContext, type: number, source: string): WebGLShader | null {
  const shader = gl.createShader(type)
  if (!shader) return null
  gl.shaderSource(shader, source)
  gl.compileShader(shader)
  if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
    console.error('[WindGL] Shader compile error:', gl.getShaderInfoLog(shader))
    gl.deleteShader(shader)
    return null
  }
  return shader
}

function createProgram(gl: WebGLRenderingContext, vs: string, fs: string): WebGLProgram | null {
  const vertShader = createShader(gl, gl.VERTEX_SHADER, vs)
  const fragShader = createShader(gl, gl.FRAGMENT_SHADER, fs)
  if (!vertShader || !fragShader) return null
  const program = gl.createProgram()
  if (!program) return null
  gl.attachShader(program, vertShader)
  gl.attachShader(program, fragShader)
  gl.linkProgram(program)
  if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
    console.error('[WindGL] Program link error:', gl.getProgramInfoLog(program))
    return null
  }
  gl.deleteShader(vertShader)
  gl.deleteShader(fragShader)
  return program
}

// ===== Particle State =====

const NUM_PARTICLES = 30000 // max buffer size (increased for zoom adaptive)

// ===== WindGL Custom Layer =====

export interface WindGLParams {
  numParticles: number
  speedFactor: number
  respawnRate: number
  particleAlpha: number
  particleColor: [number, number, number]
  colorBySpeed: boolean   // color particles by wind speed (true) or use particleColor (false)
  fadeOpacity: number     // 0-1, how much of previous frame to keep (0.96 = long trails, 0.8 = short)
  pointSize: number       // base particle point size in pixels
  zoomAdaptive: boolean   // adapt pointSize and numParticles to zoom level
  heatmapOpacity: number
  coastlineWidth: number
  coastlineOpacity: number
}

export const DEFAULT_PARAMS: WindGLParams = {
  numParticles: 16000,
  speedFactor: 0.00029,
  respawnRate: 0.007,
  particleAlpha: 0.7,
  particleColor: [1, 1, 1],
  colorBySpeed: false,
  fadeOpacity: 0.935,
  pointSize: 2.5,
  zoomAdaptive: false,
  heatmapOpacity: 0.8,
  coastlineWidth: 1.5,
  coastlineOpacity: 0.5,
}

export class WindGL {
  id = 'wind-gl-layer'
  type = 'custom' as const
  renderingMode = '2d' as const

  params: WindGLParams = { ...DEFAULT_PARAMS }

  private map: mapboxgl.Map | null = null
  private gl: WebGLRenderingContext | null = null

  // Programs
  private heatmapProgram: WebGLProgram | null = null
  private particleProgram: WebGLProgram | null = null
  private fadeProgram: WebGLProgram | null = null
  private screenProgram: WebGLProgram | null = null

  // Heatmap buffers
  private quadBuffer: WebGLBuffer | null = null
  private texCoordBuffer: WebGLBuffer | null = null
  private heatmapTexture: WebGLTexture | null = null
  private quadVertexCount = 6

  // Screen quad buffer (for FBO passes)
  private screenQuadBuffer: WebGLBuffer | null = null

  // Particle buffers
  private particleBuffer: WebGLBuffer | null = null
  private speedBuffer: WebGLBuffer | null = null
  private colorRampTexture: WebGLTexture | null = null

  // FBO ping-pong
  private fboA: WebGLFramebuffer | null = null
  private fboB: WebGLFramebuffer | null = null
  private texA: WebGLTexture | null = null
  private texB: WebGLTexture | null = null
  private fboWidth = 0
  private fboHeight = 0

  // State
  private windData: WindData | null = null
  private particleLons: Float32Array = new Float32Array(NUM_PARTICLES)
  private particleLats: Float32Array = new Float32Array(NUM_PARTICLES)
  private particleMerc: Float32Array = new Float32Array(NUM_PARTICLES * 2)
  private particleSpeeds: Float32Array = new Float32Array(NUM_PARTICLES) // normalized [0,1]
  private prevMatrix: Float32Array = new Float32Array(16)
  private _disposed = false

  onAdd(map: mapboxgl.Map, gl: WebGLRenderingContext) {
    this._disposed = false
    this.map = map
    this.gl = gl

    // Create shader programs
    this.heatmapProgram = createProgram(gl, HEATMAP_VS, HEATMAP_FS)
    this.particleProgram = createProgram(gl, PARTICLE_VS, PARTICLE_FS)
    this.fadeProgram = createProgram(gl, SCREEN_VS, FADE_FS_FIXED)
    this.screenProgram = createProgram(gl, SCREEN_VS, SCREEN_FS)

    // Heatmap buffers
    this.quadBuffer = gl.createBuffer()
    this.texCoordBuffer = gl.createBuffer()
    this.heatmapTexture = gl.createTexture()

    // Screen quad for FBO passes: full-screen triangle strip [-1,1]
    this.screenQuadBuffer = gl.createBuffer()
    gl.bindBuffer(gl.ARRAY_BUFFER, this.screenQuadBuffer)
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([
      -1, -1,  1, -1,  -1, 1,  1, 1
    ]), gl.STATIC_DRAW)

    // Particle buffers
    this.particleBuffer = gl.createBuffer()
    this.speedBuffer = gl.createBuffer()

    // Color ramp texture (256x1)
    this.colorRampTexture = gl.createTexture()
    gl.bindTexture(gl.TEXTURE_2D, this.colorRampTexture)
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, 256, 1, 0, gl.RGBA, gl.UNSIGNED_BYTE, buildColorRamp())
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)

    console.log('[WindGL] Layer added (FBO mode)')
  }

  private createFBO(gl: WebGLRenderingContext, width: number, height: number) {
    if (this.fboA) gl.deleteFramebuffer(this.fboA)
    if (this.fboB) gl.deleteFramebuffer(this.fboB)
    if (this.texA) gl.deleteTexture(this.texA)
    if (this.texB) gl.deleteTexture(this.texB)

    const createFBOPair = () => {
      const tex = gl.createTexture()!
      gl.bindTexture(gl.TEXTURE_2D, tex)
      gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, width, height, 0, gl.RGBA, gl.UNSIGNED_BYTE, null)
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)

      const fbo = gl.createFramebuffer()!
      gl.bindFramebuffer(gl.FRAMEBUFFER, fbo)
      gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, tex, 0)

      gl.clearColor(0, 0, 0, 1)
      gl.clear(gl.COLOR_BUFFER_BIT)

      return { fbo, tex }
    }

    const a = createFBOPair()
    const b = createFBOPair()

    this.fboA = a.fbo
    this.texA = a.tex
    this.fboB = b.fbo
    this.texB = b.tex
    this.fboWidth = width
    this.fboHeight = height

    // Unbind to prevent feedback loops
    gl.bindFramebuffer(gl.FRAMEBUFFER, null)
    gl.bindTexture(gl.TEXTURE_2D, null)

    console.log(`[WindGL] FBOs created: ${width}×${height}`)
  }

  setWindData(data: WindData) {
    this.windData = data
    const gl = this.gl
    if (!gl) return

    const { width, height, speeds, bounds } = data

    // Upscale texture to TEX_SIZE with bilinear interpolation
    // speeds are in km/h from the API — convert to knots for color mapping
    const TEX_SIZE = 256
    const pixels = new Uint8Array(TEX_SIZE * TEX_SIZE * 4)

    for (let texRow = 0; texRow < TEX_SIZE; texRow++) {
      const srcRowF = (texRow / (TEX_SIZE - 1)) * (height - 1)
      for (let texCol = 0; texCol < TEX_SIZE; texCol++) {
        const srcColF = (texCol / (TEX_SIZE - 1)) * (width - 1)
        const r0 = Math.max(0, Math.min(height - 1, Math.floor(srcRowF)))
        const r1 = Math.min(height - 1, r0 + 1)
        const c0 = Math.max(0, Math.min(width - 1, Math.floor(srcColF)))
        const c1 = Math.min(width - 1, c0 + 1)
        const fr = srcRowF - r0
        const fc = srcColF - c0
        const s00 = speeds[r0 * width + c0] ?? 0
        const s01 = speeds[r0 * width + c1] ?? 0
        const s10 = speeds[r1 * width + c0] ?? 0
        const s11 = speeds[r1 * width + c1] ?? 0
        const speedKmh = s00 * (1 - fr) * (1 - fc) + s01 * (1 - fr) * fc + s10 * fr * (1 - fc) + s11 * fr * fc
        const speedKts = speedKmh * KMH_TO_KTS

        const [cr, cg, cb] = speedToColor(speedKts)
        const dstIdx = (texRow * TEX_SIZE + texCol) * 4
        pixels[dstIdx] = cr
        pixels[dstIdx + 1] = cg
        pixels[dstIdx + 2] = cb
        pixels[dstIdx + 3] = 200
      }
    }

    gl.bindTexture(gl.TEXTURE_2D, this.heatmapTexture)
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, TEX_SIZE, TEX_SIZE, 0, gl.RGBA, gl.UNSIGNED_BYTE, pixels)
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)

    // Build horizontal strips for Mercator-correct positioning
    const NUM_STRIPS = 10
    const positions = new Float32Array(NUM_STRIPS * 6 * 2)
    const texcoords = new Float32Array(NUM_STRIPS * 6 * 2)
    const leftX = mapboxgl.MercatorCoordinate.fromLngLat([bounds.lonMin, 0]).x
    const rightX = mapboxgl.MercatorCoordinate.fromLngLat([bounds.lonMax, 0]).x

    for (let s = 0; s < NUM_STRIPS; s++) {
      const lat0 = bounds.latMin + (bounds.latMax - bounds.latMin) * (s / NUM_STRIPS)
      const lat1 = bounds.latMin + (bounds.latMax - bounds.latMin) * ((s + 1) / NUM_STRIPS)
      const y0 = mapboxgl.MercatorCoordinate.fromLngLat([0, lat0]).y
      const y1 = mapboxgl.MercatorCoordinate.fromLngLat([0, lat1]).y
      const ty0 = s / NUM_STRIPS
      const ty1 = (s + 1) / NUM_STRIPS

      const b = s * 12
      positions[b]    = leftX;  positions[b+1]  = y0
      positions[b+2]  = rightX; positions[b+3]  = y0
      positions[b+4]  = leftX;  positions[b+5]  = y1
      positions[b+6]  = rightX; positions[b+7]  = y0
      positions[b+8]  = rightX; positions[b+9]  = y1
      positions[b+10] = leftX;  positions[b+11] = y1

      texcoords[b]    = 0; texcoords[b+1]  = ty0
      texcoords[b+2]  = 1; texcoords[b+3]  = ty0
      texcoords[b+4]  = 0; texcoords[b+5]  = ty1
      texcoords[b+6]  = 1; texcoords[b+7]  = ty0
      texcoords[b+8]  = 1; texcoords[b+9]  = ty1
      texcoords[b+10] = 0; texcoords[b+11] = ty1
    }

    this.quadVertexCount = NUM_STRIPS * 6

    gl.bindBuffer(gl.ARRAY_BUFFER, this.quadBuffer)
    gl.bufferData(gl.ARRAY_BUFFER, positions, gl.STATIC_DRAW)

    gl.bindBuffer(gl.ARRAY_BUFFER, this.texCoordBuffer)
    gl.bufferData(gl.ARRAY_BUFFER, texcoords, gl.STATIC_DRAW)

    // Initialize particles
    this.initParticles(bounds)

    console.log(`[WindGL] Data loaded: ${width}×${height} grid`)
  }

  private initParticles(bounds: WindData['bounds']) {
    for (let i = 0; i < NUM_PARTICLES; i++) {
      this.particleLons[i] = bounds.lonMin + Math.random() * (bounds.lonMax - bounds.lonMin)
      this.particleLats[i] = bounds.latMin + Math.random() * (bounds.latMax - bounds.latMin)
    }
    this.updateParticleMercator()
  }

  private respawnParticle(i: number) {
    if (!this.windData) return
    const { bounds } = this.windData
    this.particleLons[i] = bounds.lonMin + Math.random() * (bounds.lonMax - bounds.lonMin)
    this.particleLats[i] = bounds.latMin + Math.random() * (bounds.latMax - bounds.latMin)
  }

  private updateParticleMercator() {
    for (let i = 0; i < NUM_PARTICLES; i++) {
      const mc = mapboxgl.MercatorCoordinate.fromLngLat([this.particleLons[i], this.particleLats[i]])
      this.particleMerc[i * 2] = mc.x
      this.particleMerc[i * 2 + 1] = mc.y
    }
  }

  private bilinearInterp(gridX: number, gridY: number, field: number[], width: number, height: number): number {
    const x0 = Math.floor(gridX)
    const y0 = Math.floor(gridY)
    const x1 = Math.min(x0 + 1, width - 1)
    const y1 = Math.min(y0 + 1, height - 1)
    const fx = gridX - x0
    const fy = gridY - y0

    const v00 = field[y0 * width + x0] ?? 0
    const v10 = field[y0 * width + x1] ?? 0
    const v01 = field[y1 * width + x0] ?? 0
    const v11 = field[y1 * width + x1] ?? 0

    return v00 * (1 - fx) * (1 - fy)
      + v10 * fx * (1 - fy)
      + v01 * (1 - fx) * fy
      + v11 * fx * fy
  }

  private updateParticles() {
    if (!this.windData) return
    const { u, v, width, height, bounds, speeds } = this.windData
    const lonRange = bounds.lonMax - bounds.lonMin
    const latRange = bounds.latMax - bounds.latMin

    const count = Math.min(this.params.numParticles, NUM_PARTICLES)
    const sf = this.params.speedFactor
    const rr = this.params.respawnRate

    for (let i = 0; i < count; i++) {
      const lon = this.particleLons[i]
      const lat = this.particleLats[i]

      const gridX = ((lon - bounds.lonMin) / lonRange) * (width - 1)
      const gridY = ((lat - bounds.latMin) / latRange) * (height - 1)

      const uVal = this.bilinearInterp(gridX, gridY, u, width, height)
      const vVal = this.bilinearInterp(gridX, gridY, v, width, height)

      // Compute speed for color (km/h → knots → normalized [0,1])
      const speedKmh = this.bilinearInterp(gridX, gridY, speeds, width, height)
      this.particleSpeeds[i] = Math.min(1.0, (speedKmh * KMH_TO_KTS) / MAX_SPEED_KTS)

      const cosLat = Math.cos(lat * Math.PI / 180)
      const newLon = lon + uVal * sf / Math.max(cosLat, 0.1)
      const newLat = lat + vVal * sf

      if (
        newLon < bounds.lonMin || newLon > bounds.lonMax ||
        newLat < bounds.latMin || newLat > bounds.latMax ||
        Math.random() < rr
      ) {
        this.respawnParticle(i)
      } else {
        this.particleLons[i] = newLon
        this.particleLats[i] = newLat
      }
    }

    this.updateParticleMercator()
  }

  private drawScreenQuad(gl: WebGLRenderingContext, program: WebGLProgram) {
    const aPos = gl.getAttribLocation(program, 'a_pos')
    gl.bindBuffer(gl.ARRAY_BUFFER, this.screenQuadBuffer)
    gl.enableVertexAttribArray(aPos)
    gl.vertexAttribPointer(aPos, 2, gl.FLOAT, false, 0, 0)
    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4)
    gl.disableVertexAttribArray(aPos)
  }

  // Compute zoom-adaptive values
  private getZoomAdjusted(): { count: number, pointSize: number } {
    const zoom = this.map?.getZoom() ?? 6
    if (!this.params.zoomAdaptive) {
      return { count: Math.min(this.params.numParticles, NUM_PARTICLES), pointSize: this.params.pointSize }
    }
    // At zoom 4-5 (full France): base values
    // At zoom 8+: more particles (zoomed in = less area, need density), bigger points
    // At zoom 3-: fewer particles, smaller points
    const zoomFactor = Math.pow(2, (zoom - 5) * 0.5) // exponential scaling
    const count = Math.min(
      NUM_PARTICLES,
      Math.round(this.params.numParticles * Math.max(0.3, Math.min(2.0, zoomFactor)))
    )
    const pointSize = this.params.pointSize * Math.max(0.5, Math.min(3.0, zoomFactor * 0.8))
    return { count, pointSize }
  }

  render(gl: WebGLRenderingContext, matrix: number[]) {
    if (this._disposed || !this.windData) return

    // Check if FBOs need creation/resize
    const canvas = gl.canvas as HTMLCanvasElement
    const w = canvas.width
    const h = canvas.height
    if (!this.fboA || this.fboWidth !== w || this.fboHeight !== h) {
      this.createFBO(gl, w, h)
    }

    // Save Mapbox's current framebuffer
    const prevFBO = gl.getParameter(gl.FRAMEBUFFER_BINDING)
    const prevViewport = gl.getParameter(gl.VIEWPORT)

    // Save GL state
    const prevBlend = gl.getParameter(gl.BLEND)
    const prevDepthTest = gl.getParameter(gl.DEPTH_TEST)

    gl.disable(gl.DEPTH_TEST)

    // Detect camera movement: compare current matrix to previous
    let cameraChanged = false
    for (let i = 0; i < 16; i++) {
      if (Math.abs(matrix[i] - this.prevMatrix[i]) > 1e-10) {
        cameraChanged = true
        break
      }
    }
    this.prevMatrix.set(matrix)

    // ===== Step 1: Fade pass — draw texA into fboB with reduced alpha =====
    gl.bindFramebuffer(gl.FRAMEBUFFER, this.fboB)
    gl.viewport(0, 0, w, h)

    if (this.fadeProgram) {
      gl.disable(gl.BLEND)
      gl.useProgram(this.fadeProgram)

      gl.activeTexture(gl.TEXTURE0)
      gl.bindTexture(gl.TEXTURE_2D, this.texA)
      gl.uniform1i(gl.getUniformLocation(this.fadeProgram, 'u_texture'), 0)
      // When camera moves, fade faster so stale trails disappear but keep short trails visible
      const fade = cameraChanged ? 0.7 : this.params.fadeOpacity
      gl.uniform1f(gl.getUniformLocation(this.fadeProgram, 'u_fade'), fade)

      this.drawScreenQuad(gl, this.fadeProgram)

      // Unbind texA to prevent feedback loop
      gl.bindTexture(gl.TEXTURE_2D, null)
    }

    // ===== Step 2: Draw particles into fboB =====
    this.updateParticles()
    const { count, pointSize } = this.getZoomAdjusted()

    if (this.particleProgram) {
      gl.enable(gl.BLEND)
      gl.blendFuncSeparate(gl.SRC_ALPHA, gl.ONE, gl.ZERO, gl.ONE)

      gl.useProgram(this.particleProgram)

      gl.uniformMatrix4fv(gl.getUniformLocation(this.particleProgram, 'u_matrix'), false, matrix)
      gl.uniform1f(gl.getUniformLocation(this.particleProgram, 'u_pointSize'), pointSize)
      gl.uniform1f(gl.getUniformLocation(this.particleProgram, 'u_alpha'), this.params.particleAlpha)
      gl.uniform1f(gl.getUniformLocation(this.particleProgram, 'u_useColor'), this.params.colorBySpeed ? 1.0 : 0.0)
      const [pr, pg, pb] = this.params.particleColor
      gl.uniform4f(gl.getUniformLocation(this.particleProgram, 'u_fallbackColor'), pr, pg, pb, 1.0)

      // Color ramp texture on unit 1
      gl.activeTexture(gl.TEXTURE1)
      gl.bindTexture(gl.TEXTURE_2D, this.colorRampTexture)
      gl.uniform1i(gl.getUniformLocation(this.particleProgram, 'u_colorRamp'), 1)

      // Position attribute
      const aPos = gl.getAttribLocation(this.particleProgram, 'a_pos')
      gl.bindBuffer(gl.ARRAY_BUFFER, this.particleBuffer)
      gl.bufferData(gl.ARRAY_BUFFER, this.particleMerc.subarray(0, count * 2), gl.DYNAMIC_DRAW)
      gl.enableVertexAttribArray(aPos)
      gl.vertexAttribPointer(aPos, 2, gl.FLOAT, false, 0, 0)

      // Speed attribute
      const aSpeed = gl.getAttribLocation(this.particleProgram, 'a_speed')
      gl.bindBuffer(gl.ARRAY_BUFFER, this.speedBuffer)
      gl.bufferData(gl.ARRAY_BUFFER, this.particleSpeeds.subarray(0, count), gl.DYNAMIC_DRAW)
      gl.enableVertexAttribArray(aSpeed)
      gl.vertexAttribPointer(aSpeed, 1, gl.FLOAT, false, 0, 0)

      gl.drawArrays(gl.POINTS, 0, count)

      gl.disableVertexAttribArray(aPos)
      gl.disableVertexAttribArray(aSpeed)

      // Unbind textures to prevent feedback loop
      gl.activeTexture(gl.TEXTURE1)
      gl.bindTexture(gl.TEXTURE_2D, null)
      gl.activeTexture(gl.TEXTURE0)
      gl.bindTexture(gl.TEXTURE_2D, null)
    }

    // ===== Step 3: Swap FBOs =====
    const tmpFbo = this.fboA
    const tmpTex = this.texA
    this.fboA = this.fboB
    this.texA = this.texB
    this.fboB = tmpFbo
    this.texB = tmpTex

    // ===== Step 4: Restore Mapbox framebuffer and composite =====
    gl.bindFramebuffer(gl.FRAMEBUFFER, prevFBO)
    gl.viewport(prevViewport[0], prevViewport[1], prevViewport[2], prevViewport[3])

    gl.enable(gl.BLEND)
    gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

    // Draw heatmap first
    if (this.heatmapProgram) {
      gl.useProgram(this.heatmapProgram)

      gl.uniformMatrix4fv(gl.getUniformLocation(this.heatmapProgram, 'u_matrix'), false, matrix)
      gl.uniform1f(gl.getUniformLocation(this.heatmapProgram, 'u_opacity'), this.params.heatmapOpacity)

      gl.activeTexture(gl.TEXTURE0)
      gl.bindTexture(gl.TEXTURE_2D, this.heatmapTexture)
      gl.uniform1i(gl.getUniformLocation(this.heatmapProgram, 'u_texture'), 0)

      const aPos = gl.getAttribLocation(this.heatmapProgram, 'a_pos')
      gl.bindBuffer(gl.ARRAY_BUFFER, this.quadBuffer)
      gl.enableVertexAttribArray(aPos)
      gl.vertexAttribPointer(aPos, 2, gl.FLOAT, false, 0, 0)

      const aTexcoord = gl.getAttribLocation(this.heatmapProgram, 'a_texcoord')
      gl.bindBuffer(gl.ARRAY_BUFFER, this.texCoordBuffer)
      gl.enableVertexAttribArray(aTexcoord)
      gl.vertexAttribPointer(aTexcoord, 2, gl.FLOAT, false, 0, 0)

      gl.drawArrays(gl.TRIANGLES, 0, this.quadVertexCount)

      gl.disableVertexAttribArray(aPos)
      gl.disableVertexAttribArray(aTexcoord)
    }

    // Composite particle FBO
    if (this.screenProgram) {
      gl.useProgram(this.screenProgram)

      gl.activeTexture(gl.TEXTURE0)
      gl.bindTexture(gl.TEXTURE_2D, this.texA)
      gl.uniform1i(gl.getUniformLocation(this.screenProgram, 'u_texture'), 0)
      gl.uniform1f(gl.getUniformLocation(this.screenProgram, 'u_opacity'), 1.0)

      gl.blendFuncSeparate(gl.ONE, gl.ONE, gl.ZERO, gl.ONE)

      this.drawScreenQuad(gl, this.screenProgram)

      gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
    }

    // Restore GL state
    if (!prevBlend) gl.disable(gl.BLEND)
    if (prevDepthTest) gl.enable(gl.DEPTH_TEST)

    // Request next frame
    if (this.map) this.map.triggerRepaint()
  }

  onRemove(_map: mapboxgl.Map, gl: WebGLRenderingContext) {
    this._disposed = true
    if (this.heatmapProgram) gl.deleteProgram(this.heatmapProgram)
    if (this.particleProgram) gl.deleteProgram(this.particleProgram)
    if (this.fadeProgram) gl.deleteProgram(this.fadeProgram)
    if (this.screenProgram) gl.deleteProgram(this.screenProgram)
    if (this.quadBuffer) gl.deleteBuffer(this.quadBuffer)
    if (this.texCoordBuffer) gl.deleteBuffer(this.texCoordBuffer)
    if (this.particleBuffer) gl.deleteBuffer(this.particleBuffer)
    if (this.speedBuffer) gl.deleteBuffer(this.speedBuffer)
    if (this.screenQuadBuffer) gl.deleteBuffer(this.screenQuadBuffer)
    if (this.heatmapTexture) gl.deleteTexture(this.heatmapTexture)
    if (this.colorRampTexture) gl.deleteTexture(this.colorRampTexture)
    if (this.fboA) gl.deleteFramebuffer(this.fboA)
    if (this.fboB) gl.deleteFramebuffer(this.fboB)
    if (this.texA) gl.deleteTexture(this.texA)
    if (this.texB) gl.deleteTexture(this.texB)
    console.log('[WindGL] Layer removed, resources cleaned up')
  }

  /** Get interpolated wind data at a geographic point. Returns null if outside bounds. */
  getWindAtPoint(lon: number, lat: number): { speedKts: number, directionDeg: number, u: number, v: number } | null {
    if (!this.windData) return null
    const { u, v, speeds, width, height, bounds } = this.windData

    if (lon < bounds.lonMin || lon > bounds.lonMax || lat < bounds.latMin || lat > bounds.latMax) return null

    const gridX = ((lon - bounds.lonMin) / (bounds.lonMax - bounds.lonMin)) * (width - 1)
    const gridY = ((lat - bounds.latMin) / (bounds.latMax - bounds.latMin)) * (height - 1)

    const uVal = this.bilinearInterp(gridX, gridY, u, width, height)
    const vVal = this.bilinearInterp(gridX, gridY, v, width, height)
    const speedKmh = this.bilinearInterp(gridX, gridY, speeds, width, height)
    const speedKts = speedKmh * KMH_TO_KTS

    // Wind direction: meteorological convention (where wind comes FROM)
    // u = east component, v = north component
    const dirRad = Math.atan2(-uVal, -vVal)
    const directionDeg = ((dirRad * 180 / Math.PI) + 360) % 360

    return { speedKts: Math.round(speedKts * 10) / 10, directionDeg: Math.round(directionDeg), u: uVal, v: vVal }
  }

  dispose() {
    this._disposed = true
  }
}
