import Link from 'next/link'

export default function PrivacyPage() {
  return (
    <div className="min-h-screen bg-[#0a0a0a] text-white overflow-y-auto">
      <nav className="fixed top-0 left-0 right-0 z-50 backdrop-blur-xl bg-[#0a0a0a]/80 border-b border-white/5">
        <div className="max-w-3xl mx-auto px-6 h-16 flex items-center">
          <Link href="/" className="flex items-center gap-3 hover:opacity-80 transition-opacity">
            <div className="w-8 h-8 rounded-lg bg-gradient-to-br from-cyan-400 to-cyan-600 flex items-center justify-center text-sm font-bold">
              V
            </div>
            <span className="text-lg font-semibold">Le Vent</span>
          </Link>
        </div>
      </nav>

      <main className="pt-28 pb-20 px-6">
        <div className="max-w-3xl mx-auto prose prose-invert prose-sm">
          <h1 className="text-3xl font-bold mb-8">Politique de confidentialite</h1>
          <p className="text-gray-400 text-sm mb-8">Derniere mise a jour : fevrier 2025</p>

          <section className="mb-8">
            <h2 className="text-xl font-semibold mb-3">Introduction</h2>
            <p className="text-gray-300 leading-relaxed">
              Le Vent est une application gratuite de consultation de donnees meteorologiques.
              Nous nous engageons a proteger votre vie privee. Cette politique explique comment
              nous traitons vos donnees.
            </p>
          </section>

          <section className="mb-8">
            <h2 className="text-xl font-semibold mb-3">Donnees collectees</h2>
            <div className="bg-white/5 border border-white/5 rounded-xl p-5 mb-4">
              <h3 className="text-base font-medium mb-2 text-cyan-400">Localisation approximative</h3>
              <p className="text-gray-400 text-sm leading-relaxed">
                L&apos;app utilise votre position GPS uniquement pour centrer la carte sur votre zone
                et afficher les stations les plus proches. Cette donnee reste sur votre appareil
                et n&apos;est jamais envoyee a nos serveurs ni partagee avec des tiers.
              </p>
            </div>
            <div className="bg-white/5 border border-white/5 rounded-xl p-5">
              <h3 className="text-base font-medium mb-2 text-cyan-400">Preferences locales</h3>
              <p className="text-gray-400 text-sm leading-relaxed">
                Vos favoris, alertes et reglages sont stockes localement sur votre appareil
                via UserDefaults. Aucune donnee personnelle n&apos;est transmise.
              </p>
            </div>
          </section>

          <section className="mb-8">
            <h2 className="text-xl font-semibold mb-3">Donnees NON collectees</h2>
            <ul className="text-gray-400 space-y-2 text-sm">
              <li className="flex items-start gap-2">
                <span className="text-green-400 mt-0.5">&#10003;</span>
                Aucun identifiant publicitaire ou tracking
              </li>
              <li className="flex items-start gap-2">
                <span className="text-green-400 mt-0.5">&#10003;</span>
                Aucune analyse d&apos;utilisation (pas de Firebase, Amplitude, etc.)
              </li>
              <li className="flex items-start gap-2">
                <span className="text-green-400 mt-0.5">&#10003;</span>
                Aucun partage de donnees avec des tiers
              </li>
              <li className="flex items-start gap-2">
                <span className="text-green-400 mt-0.5">&#10003;</span>
                Aucune creation de compte requise
              </li>
              <li className="flex items-start gap-2">
                <span className="text-green-400 mt-0.5">&#10003;</span>
                Aucun cookie
              </li>
            </ul>
          </section>

          <section className="mb-8">
            <h2 className="text-xl font-semibold mb-3">Services tiers</h2>
            <p className="text-gray-300 leading-relaxed text-sm">
              L&apos;app recupere des donnees meteorologiques depuis des APIs publiques :
              Meteo France, FFVL, Pioupiou, Holfuy, Wind France, CANDHIS et SHOM.
              Ces requetes ne contiennent aucune donnee personnelle.
            </p>
            <p className="text-gray-300 leading-relaxed text-sm mt-3">
              L&apos;integration WindsUp est optionnelle. Si vous choisissez de vous connecter,
              vos identifiants sont stockes localement et envoyes uniquement a l&apos;API WindsUp
              pour l&apos;authentification.
            </p>
          </section>

          <section className="mb-8">
            <h2 className="text-xl font-semibold mb-3">Contact</h2>
            <p className="text-gray-300 text-sm">
              Pour toute question concernant cette politique, contactez-nous a :{' '}
              <a href="mailto:music.music.music18@gmail.com" className="text-cyan-400 hover:underline">
                music.music.music18@gmail.com
              </a>
            </p>
          </section>
        </div>
      </main>

      <footer className="border-t border-white/5 py-8 px-6">
        <div className="max-w-3xl mx-auto flex items-center justify-between text-sm text-gray-600">
          <Link href="/" className="hover:text-gray-400 transition-colors">
            Retour a l&apos;accueil
          </Link>
          <span>2025 Le Vent</span>
        </div>
      </footer>
    </div>
  )
}
