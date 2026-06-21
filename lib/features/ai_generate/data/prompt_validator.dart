/// Pre-flight check del prompt antes de mandar al worker IA.
/// Bloquea prompts que claramente piden contenido prohibido por la
/// política de Google Play (NSFW, violencia gráfica, copyright, etc).
///
/// Esta es la PRIMERA línea de defensa — el backend / modelo IA ya tiene
/// sus propios filtros (Gemini/Nano-Banana rechazan internamente), pero
/// el rechazo del servidor cuesta crédito + tiempo. Bloquearlo cliente
/// ahorra ambos y le da al user un mensaje claro.
///
/// La lista es deliberadamente conservadora — match exacto de palabras
/// (no substring) para no bloquear "scary movie" por contener "ass".
class PromptValidator {
  PromptValidator._();

  // Categorías de keywords prohibidas. Mantén las listas en lowercase
  // — el matcher pasa el input por toLowerCase().
  static const _nsfw = <String>{
    'nude',
    'naked',
    'nudity',
    'desnudo',
    'desnuda',
    'desnudos',
    'sexy',
    'sexual',
    'porn',
    'porno',
    'pornography',
    'pornografía',
    'erotic',
    'erotico',
    'erotica',
    'erótico',
    'erótica',
    'nsfw',
    'xxx',
    'hentai',
    'lewd',
    'horny',
    'orgasm',
    'orgasmo',
    'boobs',
    'tits',
    'tetas',
    'pene',
    'penis',
    'vagina',
    'pussy',
    'topless',
    'lingerie',
    'thong',
    'tanga',
    'bikini-off',
    'cum',
    'masturb',
    'fetish',
    'fetiche',
    'undress',
    'undressing',
    'undressed',
  };

  static const _violence = <String>{
    'kill',
    'murder',
    'asesinato',
    'gore',
    'blood',
    'sangre',
    'beheading',
    'decapitación',
    'torture',
    'tortura',
    'massacre',
    'masacre',
    'slaughter',
    'mutilation',
    'suicide',
    'suicidio',
    'self-harm',
    'autolesion',
    'corpse',
    'cadáver',
    'cadaver',
    'dismember',
  };

  static const _hate = <String>{
    'nazi', 'hitler', 'kkk', 'genocide', 'genocidio',
    'lynching', 'linchamiento',
    // Slurs are intentionally kept short — full list lives server-side
    // in the moderation system. Client lo bloquea para evitar request.
  };

  static const _drugs = <String>{
    'cocaine',
    'cocaína',
    'cocaina',
    'heroin',
    'heroína',
    'heroina',
    'meth',
    'metanfetamina',
    'crack pipe',
    'bong',
    'fentanyl',
    'fentanilo',
  };

  /// Famous figures + brands we shouldn't be generating likenesses of
  /// without permission. Not exhaustive — model also blocks server-side.
  static const _copyright = <String>{
    'taylor swift', 'beyonce', 'beyoncé', 'rihanna', 'drake',
    'elon musk', 'trump', 'biden', 'putin', 'obama',
    'cristiano ronaldo', 'lionel messi', 'leo messi',
    'disney logo', 'nike logo', 'mcdonalds logo',
    // Characters owned by big studios — we already publish licensed-look
    // wallpapers (Goku, Mario, Pokemon) curated manually; user-gen of
    // those gets blocked to avoid IP issues at scale.
    'mickey mouse', 'spiderman', 'iron man', 'batman trademark',
  };

  /// Returns `null` if the prompt passes, otherwise a short reason string
  /// the UI can show to the user (es-MX).
  static String? checkSpanish(String prompt) {
    final low = prompt.toLowerCase();
    if (_hits(low, _nsfw) != null) {
      return 'Tu prompt parece pedir contenido sexual o desnudez, que no permitimos.';
    }
    if (_hits(low, _violence) != null) {
      return 'Tu prompt parece pedir violencia gráfica, que no permitimos.';
    }
    if (_hits(low, _hate) != null) {
      return 'Tu prompt incluye términos de odio que no permitimos.';
    }
    if (_hits(low, _drugs) != null) {
      return 'Tu prompt parece pedir contenido de drogas ilegales.';
    }
    final cp = _hits(low, _copyright);
    if (cp != null) {
      return 'Tu prompt menciona "$cp" — no podemos generar imágenes de personas reales ni marcas registradas.';
    }
    return null;
  }

  /// English variant of [checkSpanish].
  static String? checkEnglish(String prompt) {
    final low = prompt.toLowerCase();
    if (_hits(low, _nsfw) != null) {
      return 'Your prompt seems to request sexual or nudity content, which is not allowed.';
    }
    if (_hits(low, _violence) != null) {
      return 'Your prompt seems to request graphic violence, which is not allowed.';
    }
    if (_hits(low, _hate) != null) {
      return 'Your prompt includes hateful terms that are not allowed.';
    }
    if (_hits(low, _drugs) != null) {
      return 'Your prompt seems to request illegal drug content.';
    }
    final cp = _hits(low, _copyright);
    if (cp != null) {
      return 'Your prompt mentions "$cp" — we cannot generate images of real people or trademarks.';
    }
    return null;
  }

  /// Word-boundary match — returns the matched token (for the copyright
  /// branch to quote it back at the user) or null if no hit. Trades
  /// regex compile cost for substring false-positives.
  static String? _hits(String lowText, Set<String> bag) {
    for (final term in bag) {
      // Multi-word terms: substring search is fine — they're specific.
      if (term.contains(' ')) {
        if (lowText.contains(term)) return term;
        continue;
      }
      // Single words: require word boundaries so "ass" doesn't match "pass".
      final re = RegExp(r'\b' + RegExp.escape(term) + r'\b');
      if (re.hasMatch(lowText)) return term;
    }
    return null;
  }
}
