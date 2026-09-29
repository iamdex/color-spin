// Leaderboard names: the ones that are offensive (Italian and English) are not
// shown. A name is normalized first, so the usual tricks don't get through:
// accents, capitals, digits for letters (c4zz0), symbols between letters
// (f.u.c.k) and repeated letters (stroooonzo).
//
// Two lists: ROOTS are found anywhere in the name, so they are long or
// unambiguous; WORDS are short and match only as a whole word, so that
// "Cassandra", "Assunta" or "Nazionale" stay allowed.

const ROOTS = [
  // Italian
  'cazz', 'stronz', 'puttan', 'troia', 'merd', 'vaffanc', 'fancul', 'coglion', 'minchi',
  'froci', 'ricchion', 'bastard', 'bocchin', 'pompin', 'sborr', 'zoccol', 'mignott',
  'porcodio', 'dioporco', 'diocane', 'porcamadonna', 'madonnaputtana', 'dioboia', 'diomerda',
  'negro', 'negra', 'terrone', 'handicappat', 'ritardat',
  // English
  'fuck', 'shit', 'cunt', 'bitch', 'nigg', 'fagg', 'whore', 'slut', 'porn', 'pussy',
  'asshole', 'bastard', 'rapist', 'retard', 'penis', 'vagina', 'dildo', 'wank', 'motherf',
  'hitler', 'heilh', 'siegheil', 'nazis', 'jihad', 'pedofil', 'pedophil', 'molest',
];
const WORDS = [
  'cul', 'culo', 'figa', 'fica', 'pene', 'tette', 'zizze',
  'ass', 'fag', 'cock', 'dick', 'rape', 'nazi', 'kkk', 'isis', 'anal', 'sex', 'sexy',
  'cum', 'tits', 'hoe', 'nig', 'twat', 'pedo',
];
// Harmless words that contain a root, taken out before looking for roots.
const SAFE = ['scunthorpe', 'negroni', 'montenegr', 'penistone', 'cumberland'];

// Letters written as digits or symbols.
const LEET = { 0: 'o', 1: 'i', 3: 'e', 4: 'a', 5: 's', 7: 't', 8: 'b', 9: 'g', '@': 'a', $: 's', '!': 'i', '€': 'e', '|': 'i' };

const plain = s => s.normalize('NFD').replace(/\p{M}/gu, '').toLowerCase()
  .replace(/[0-9@$!€|]/g, c => LEET[c] || c).replace(/ph/g, 'f');
const collapse = s => s.replace(/(.)\1+/g, '$1');

const COLLAPSED_ROOTS = ROOTS.map(collapse);
const WORD_SET = new Set([...WORDS, ...WORDS.map(collapse)]);

/** True when the name contains an offensive word. */
export function isOffensive(name) {
  const p = plain(name);
  // All the letters together (catches f.u.c.k and "vaffan culo"), with and without repeats.
  const joined = SAFE.reduce((s, w) => s.replaceAll(w, ''), p.replace(/[^a-z]/g, ''));
  if (ROOTS.some(r => joined.includes(r)) || COLLAPSED_ROOTS.some(r => collapse(joined).includes(r))) return true;
  // Word by word, for the short ones. Single letters split by symbols (d.i.c.k) count as a word.
  const words = p.split(/[^a-z]+/).filter(Boolean);
  const spelled = /^([a-z][^a-z]+)+[a-z]$/.test(p.replace(/\s+/g, '')) ? [joined] : [];
  return [...words, ...spelled].some(w => WORD_SET.has(w) || WORD_SET.has(collapse(w)));
}
