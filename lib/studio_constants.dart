// Constants ported 1:1 from the extension's background.js:
// story arcs, variation strengths, default stage templates, Zedge rules.
import 'dart:math' as math;

import 'models.dart';

const int kPortraitWidth = 1620;
const int kPortraitHeight = 2880;
const int kLandscapeWidth = 2800;
const int kLandscapeHeight = 2400;
const int kMaxZedgeBytes = 8 * 1024 * 1024;
const int kSafeZedgeTargetBytes = 8150000;
const int kMinZedgeWidth = 1620;
const int kMinZedgeHeight = 2880;
const int kMaxZedgeMegapixels = 25000000;

const List<String> kZedgeCategories = [
  'ANIMALS',
  'ANIME',
  'CARS_N_VEHICLES',
  'COMICS',
  'DESIGNS',
  'DRAWINGS',
  'ENTERTAINMENT',
  'FUNNY',
  'GAMES',
  'HOLIDAYS',
  'LOVE',
  'MUSIC',
  'NATURE',
  'PATTERNS',
  'PEOPLE',
  'SAYINGS',
  'SPACE',
  'SPIRITUAL',
  'SPORTS',
  'TECHNOLOGY',
];

const String kNoTextGuard =
    ', no text, no letters, no numbers, no symbols, no icons, no watermark';
const String kProFinishSuffix =
    ', one strong focal point, clean uncluttered composition, professional wallpaper finish';

const String kDefaultNegativePrompt =
    'no text, no letters, no numbers, no percentage signs, no battery icons, '
    'no UI widgets, no clock, no watermark, no signature, no logo, no blurry '
    'details, no deformed anatomy';

/// Foldable adaptation prompt (v58): fixed backend text. It used to
/// be an editable field in the Studio screen; the user asked for it
/// to live in the backend only, so the engine always applies this
/// exact text and the UI never shows it.
const String kFoldableAdaptationPrompt =
    'make it landscape mode, re-frame the exact same artwork for a foldable screen without cropping the main subject';

const Map<String, String> kVariationStrengths = {
  'subtle':
      'Relight the reference image so it matches the ABSOLUTE lighting state described above - treat the stated lit-area, brightness, bloom and shadow values as exact targets to hit, not as a nudge from the reference. The change must be clearly noticeable side by side. Keep the exact same subject, objects, background, layout, composition, framing and art style: nothing may be added, removed or rearranged.',
  'clear':
      'This is a relighting edit, not a copy: rebuild the light and atmosphere of the reference image until it matches the ABSOLUTE state described above - hit the stated lit-area percentage, brightness, bloom radius and shadow depth exactly, even if that means a large jump from the reference. The result must be immediately distinguishable at a glance from any other stage. Keep the exact same subject, objects, background, layout, composition, framing and art style: nothing may be added, removed or rearranged.',
  'strong':
      'Dramatically relight the reference image to the ABSOLUTE state described above: push the stated lit-area percentage, brightness, bloom radius and shadow depth to the limit - bold light direction and color temperature, intense glow and bloom, thick atmosphere - an unmistakable transformation that can never be confused with a neighbouring stage. Keep the exact same subject, objects, background, layout, composition and framing: absolutely nothing may be added, removed or rearranged.',
};

const Map<String, List<String>> kStoryArcs24h = {
  'light': [
    ', 6 am dawn: key light low on the horizon from the left at about 10 degrees elevation, roughly 3000K rose-gold color temperature, long soft shadows stretching to the right, low-lying mist, cool blue shadow tones, high-key gentle contrast, fresh tranquil mood',
    ', 1 pm midday: key light almost straight overhead at about 80 degrees elevation, roughly 5600K neutral white daylight, short hard shadows directly under the subject, no mist, maximum color saturation and micro-detail, bright high-contrast clarity',
    ', 6 pm golden hour: key light raking in low from the right at about 8 degrees elevation, roughly 2200K amber-orange color temperature, long dramatic shadows falling to the left, warm haze and strong rim light tracing every edge, glowing low-sun flare',
    ', 11 pm night: no sun, only cool moonlight from high behind at roughly 7500K deep indigo, about 70 percent of the frame in deep shadow, silver specular highlights on edges only, soft local glow from the scene own light sources, low-key nocturnal calm',
  ],
  'bloom': [
    ', soft dawn light, the subject newly awakening, delicate buds beginning to open, rose-gold glow, misty fresh atmosphere',
    ', harsh midday sun, the subject in full bloom at its peak, vivid saturated colors lit brightly, intense vitality',
    ', ember-orange sunset light, the subject mature and complete, warm glowing rim light on its form, rich dramatic warmth',
    ', cold moonlight, the subject at rest gently closed, silver highlights on its silhouette, deep blue calm',
  ],
  'rhythm': [
    ', soft pale dawn light, the scene calm and nearly empty, misty quiet atmosphere, gentle stillness',
    ', harsh bright midday light, the scene alive with movement, sharp shadows, vivid energetic clarity',
    ', ember-orange evening light, long dramatic shadows, warm glowing atmosphere as the light fades',
    ', cold blue moonlight, the scene asleep and empty, deep shadows, silent tranquil mood',
  ],
};

const Map<String, List<String>> kStoryArcsBattery = {
  'energy': [
    ', charge level 0 of 100: the scene is almost completely dark, about 5 percent of the frame carries any light, a single dim ember of its own glow hue no larger than a coin, no bloom, no light spill, deep crushed black shadows filling the rest of the frame',
    ', charge level 20 of 100: about 20 percent of the frame is lit, the glow is a thin low-intensity core with a tight halo roughly twice its own size, faint light spill on the nearest surface only, the outer two thirds of the frame still sit in deep shadow',
    ', charge level 40 of 100: about 40 percent of the frame is lit, the glow core is clearly brighter and its halo now reaches roughly a quarter of the frame width, visible light rays and reflections on mid-distance surfaces, shadows softened to dark grey but the frame edges stay dark',
    ', charge level 60 of 100: about 60 percent of the frame is lit and roughly two stops brighter than the previous stage, the glow core is burning hot with a wide bloom reaching half the frame width, strong rays and reflections across the whole mid-ground, only the frame corners remain dark',
    ', charge level 80 of 100: about 80 percent of the frame is lit and clearly brighter again, the glow core is near-white hot at its center, heavy bloom with visible lens flare and volumetric light beams crossing the frame, bright haze filling the air, barely any shadow left except thin contact shadows',
    ', charge level 100 of 100: the whole frame is flooded with light at maximum output, the glow core is blown out pure white at its center with saturated hue at its rim, extreme bloom covering the entire frame, strong star-burst flare, glowing atmospheric haze everywhere, zero dark areas anywhere in the image',
  ],
  'growth': [
    ', charge 0 of 100: a tiny seed of the subject occupying about a tenth of the frame height in near-darkness, about 5 percent of the frame lit by one faint ember of its own glow hue',
    ', charge 20 of 100: the subject sprouting to about a quarter of the frame height, about 20 percent of the frame lit, the same hue a thin core with a tight halo, the rest in deep shadow',
    ', charge 40 of 100: the subject at about half the frame height, about 40 percent of the frame lit, the identical hue brighter with a halo a quarter of the frame wide, rays and reflections appearing',
    ', charge 60 of 100: the subject filling about two thirds of the frame and two stops brighter, the same hue burning hot, bloom across half the frame, only corners dark',
    ', charge 80 of 100: the subject near-monumental filling most of the frame, about 80 percent of the frame lit, the unchanged hue near-white hot, heavy bloom, flare and volumetric beams',
    ', charge 100 of 100: the subject monumental and dominating the frame, the whole image flooded at maximum output in the same hue, blown out white core, extreme bloom, star-burst flare, zero dark areas',
  ],
  'awaken': [
    ', charge 0 of 100: the subject dormant and perfectly still, about 5 percent of the frame lit by a dying ember of its own glow hue, no bloom, crushed black surroundings',
    ', charge 20 of 100: the first stir, about 20 percent of the frame lit, one thin crack of the same hue with a tight halo breaking the dark, everything else in deep shadow',
    ', charge 40 of 100: the subject stirring awake with gentle motion, about 40 percent of the frame lit, the identical hue spreading, halo a quarter of the frame wide, rays and reflections at mid distance',
    ', charge 60 of 100: the subject active and dynamic, about 60 percent of the frame lit and two stops brighter, the same hue burning hot, bloom across half the frame, motion trails, only corners dark',
    ', charge 80 of 100: the subject intensely alive, about 80 percent of the frame lit, the unchanged hue near-white hot, heavy bloom, lens flare, volumetric beams, energy streaming off its form',
    ', charge 100 of 100: the subject at explosive peak vitality, the whole frame flooded at maximum output in the exact same hue, blown out white core, extreme bloom and star-burst flare, zero dark areas',
  ],
};

String suggest24hArc(String prompt) {
  final p = prompt.toLowerCase();
  const bloomWords = [
    'flower',
    'lotus',
    'bloom',
    'blossom',
    'plant',
    'tree',
    'leaf',
    'leaves',
    'garden',
    'petal',
    'rose',
    'nature',
    'forest',
    'flora'
  ];
  if (bloomWords.any(p.contains)) return 'bloom';
  const rhythmWords = [
    'city',
    'street',
    'urban',
    'people',
    'crowd',
    'market',
    'traffic',
    'cafe',
    'town',
    'village',
    'lifestyle'
  ];
  if (rhythmWords.any(p.contains)) return 'rhythm';
  return 'light';
}

String suggestBatteryArc(String prompt) {
  final p = prompt.toLowerCase();
  const growthWords = [
    'flower',
    'plant',
    'tree',
    'seed',
    'leaf',
    'garden',
    'crystal',
    'bloom',
    'nature',
    'lotus'
  ];
  if (growthWords.any(p.contains)) return 'growth';
  const awakenWords = [
    'creature',
    'dragon',
    'animal',
    'being',
    'spirit',
    'robot',
    'phoenix',
    'bird',
    'beast'
  ];
  if (awakenWords.any(p.contains)) return 'awaken';
  return 'energy';
}

String buildNegativeGuard(String negativePrompt) {
  final custom = negativePrompt.trim();
  if (custom.isEmpty || custom == kDefaultNegativePrompt) {
    return custom.isEmpty ? kNoTextGuard : ', strictly avoid: $custom';
  }
  return '$kNoTextGuard, strictly avoid / negative prompt: $custom';
}

String buildStyleSuffix(String displayTarget, String colorBoost) {
  var out = '';
  if (displayTarget == 'amoled') {
    out +=
        ', high contrast, vivid luminous colors, optimized for AMOLED displays';
  } else if (displayTarget == 'ips') {
    out +=
        ', balanced brightness, natural color reproduction, optimized for IPS displays';
  }
  if (colorBoost == 'subtle') {
    out += ', subtly enhanced color richness';
  } else if (colorBoost == 'vivid') {
    out += ', vivid rich colors with enhanced saturation';
  } else if (colorBoost == 'neon') {
    out += ', bold electrifying colors, striking chromatic intensity';
  }
  return out;
}

String buildImagePrompt(
    String rawPrompt, String aspectRatio, bool forceImagePrefix) {
  var prompt = rawPrompt.trim();
  final hasImageVerb = RegExp(
          r'^(generate|create|draw|make|paint|render|design)\s+(an?\s+)?(image|picture|photo|illustration|art|wallpaper)',
          caseSensitive: false)
      .hasMatch(prompt);
  if (forceImagePrefix && !hasImageVerb) {
    prompt = 'Generate an image of: $prompt';
  }
  if (aspectRatio.isNotEmpty &&
      aspectRatio != 'auto' &&
      !prompt.toLowerCase().contains('aspect ratio')) {
    prompt = '$prompt (aspect ratio $aspectRatio)';
  }
  return prompt;
}

/// Enforces the Zedge size rules exactly like normalizeZedgeDimensions().
({int width, int height}) normalizeZedgeDimensions(int width, int height,
    {bool enforce = true}) {
  var w = width == 0 ? kPortraitWidth : width;
  var h = height == 0 ? kPortraitHeight : height;
  if (enforce) {
    if (w < kMinZedgeWidth || h < kMinZedgeHeight) {
      final scaleW = kMinZedgeWidth / w;
      final scaleH = kMinZedgeHeight / h;
      final scale = scaleW > scaleH ? scaleW : scaleH;
      w = (w * scale).round();
      if (w < kMinZedgeWidth) w = kMinZedgeWidth;
      h = (h * scale).round();
      if (h < kMinZedgeHeight) h = kMinZedgeHeight;
    }
    if (w * h >= kMaxZedgeMegapixels) {
      final downScale = math.sqrt(24500000 / (w * h));
      w = (w * downScale).floor();
      if (w < kMinZedgeWidth) w = kMinZedgeWidth;
      h = (h * downScale).floor();
      if (h < kMinZedgeHeight) h = kMinZedgeHeight;
    }
  }
  return (width: w, height: h);
}

const List<StageDef> kDualStages = [
  StageDef(
    key: 'lock',
    distSlot: 'lock',
    zipName: 'lock.jpg',
    slotIndex: 1,
    role: 'dual_lock',
    badge: 'Lock Screen (1/2)',
    shortLabel: 'Lock',
    exactFilename: 'WP_Dual_1_LockScreen.jpg',
    isAnchor: true,
    promptSuffix:
        ', lock screen framing: macro close-up, the hero fills about 80 percent of the frame height, shallow depth of field with a softly blurred background, striking fine surface detail, hero mass in the lower two thirds',
  ),
  StageDef(
    key: 'home',
    distSlot: 'home',
    zipName: 'home.jpg',
    slotIndex: 2,
    role: 'dual_home',
    badge: 'Home Screen (2/2)',
    shortLabel: 'Home',
    exactFilename: 'WP_Dual_2_HomeScreen.jpg',
    transitionInstruction:
        ', home screen framing: wide establishing view of the same scene pulled far back, the hero now occupies only about 30 percent of the frame height and sits low, deep focus, generous calm negative space and quiet low-detail area across the upper half for icons and widgets',
  ),
];

const List<StageDef> k24hStages = [
  StageDef(
    key: 'morning',
    distSlot: 'morning',
    zipName: 'morning.jpg',
    slotIndex: 1,
    role: 'time_morning',
    badge: 'Morning (1/4)',
    shortLabel: 'Morning',
    exactFilename: 'WP_24Hour_1_Morning.jpg',
    isAnchor: true,
  ),
  StageDef(
    key: 'afternoon',
    distSlot: 'afternoon',
    zipName: 'afternoon.jpg',
    slotIndex: 2,
    role: 'time_afternoon',
    badge: 'Afternoon (2/4)',
    shortLabel: 'Afternoon',
    exactFilename: 'WP_24Hour_2_Afternoon.jpg',
  ),
  StageDef(
    key: 'evening',
    distSlot: 'evening',
    zipName: 'evening.jpg',
    slotIndex: 3,
    role: 'time_evening',
    badge: 'Evening (3/4)',
    shortLabel: 'Evening',
    exactFilename: 'WP_24Hour_3_Evening.jpg',
  ),
  StageDef(
    key: 'night',
    distSlot: 'night',
    zipName: 'night.jpg',
    slotIndex: 4,
    role: 'time_night',
    badge: 'Night (4/4)',
    shortLabel: 'Night',
    exactFilename: 'WP_24Hour_4_Night.jpg',
  ),
];

const List<StageDef> kBatteryStages = [
  StageDef(
    key: 'critical',
    distSlot: 'critical',
    zipName: '0.jpg',
    slotIndex: 1,
    role: 'battery_l1',
    badge: 'Level 1: 0-20% Critical',
    shortLabel: '0% (Critical)',
    exactFilename: 'WP_Battery_Level1_Critical.jpg',
  ),
  StageDef(
    key: 'low',
    distSlot: 'low',
    zipName: '20.jpg',
    slotIndex: 2,
    role: 'battery_l2',
    badge: 'Level 2: 21-40% Low',
    shortLabel: '20% (Low)',
    exactFilename: 'WP_Battery_Level2_Low.jpg',
  ),
  StageDef(
    key: 'mid',
    distSlot: 'mid',
    zipName: '40.jpg',
    slotIndex: 3,
    role: 'battery_l3',
    badge: 'Level 3: 41-60% Mid',
    shortLabel: '40% (Mid)',
    exactFilename: 'WP_Battery_Level3_Mid.jpg',
    isAnchor: true,
  ),
  StageDef(
    key: 'high',
    distSlot: 'high',
    zipName: '60.jpg',
    slotIndex: 4,
    role: 'battery_l4',
    badge: 'Level 4: 61-80% High',
    shortLabel: '60% (High)',
    exactFilename: 'WP_Battery_Level4_High.jpg',
  ),
  StageDef(
    key: 'full',
    distSlot: 'full',
    zipName: '80.jpg',
    slotIndex: 5,
    role: 'battery_l5',
    badge: 'Level 5: 81-100% Full',
    shortLabel: '80% (Full)',
    exactFilename: 'WP_Battery_Level5_Full.jpg',
  ),
  StageDef(
    key: 'charging',
    distSlot: 'charging',
    zipName: '100.jpg',
    slotIndex: 6,
    role: 'battery_charging',
    badge: 'Charging (100% Active)',
    shortLabel: '100% (Charging)',
    exactFilename: 'WP_Battery_Charging.jpg',
  ),
];

List<StageDef> stagesForMode(String workflowMode) {
  switch (workflowMode) {
    case 'set_dual':
      return kDualStages;
    case 'set_battery':
      return kBatteryStages;
    case 'set_24h':
    default:
      return k24hStages;
  }
}

String setTypeLabelFor(String workflowMode) {
  switch (workflowMode) {
    case 'set_dual':
      return 'Dual Wallpaper Set (2 JPGs)';
    case 'set_battery':
      return 'Battery Level Wallpaper Set (6 JPGs)';
    case 'single':
      return 'Single Wallpaper';
    case 'img2img_file':
      return 'Imported / Reference Set';
    case 'set_24h':
    default:
      return '24-Hour Wallpaper Set (4 JPGs)';
  }
}

String slugify(String input, {int maxLen = 32}) {
  var s = input.toLowerCase().replaceAll(RegExp(r'\.[^.]+$'), '');
  s = s
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  if (s.length > maxLen) s = s.substring(0, maxLen);
  return s.isEmpty ? 'wallpaper_set' : s;
}
