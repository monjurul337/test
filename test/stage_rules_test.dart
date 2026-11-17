// v80: the four modes' rules prompts, matched against the
// generate-main ZIP (image_Generator.zip) the user sent —
// SetTypes.variants + SetArcs + the Single Landscape variant.
// What the ZIP says:
//   - 24h 'light' arc = soft light-only progression (NOT the precise
//     Morning/Afternoon/Evening/Night variant texts — those are the
//     static fallback, now the StageDef promptSuffixes).
//   - Battery 'energy' arc = short "charge N of 100" texts (NOT the
//     detailed charge-level ladder — that is the StageDef fallback).
//   - Single+Foldable = the full Landscape variant rules text.
//   - The no-text guard is appended by the engine, never baked into
//     the constants.
import 'package:flutter_test/flutter_test.dart';
import 'package:gemini_hd_studio/studio_constants.dart';

void main() {
  test('24h light arc is the soft progression from the ZIP', () {
    final light = kStoryArcs24h['light']!;
    expect(light.length, 4);
    expect(
        light[0],
        ', soft dawn light washing over the scene, warm rose-gold color temperature, gentle misty atmosphere, delicate long soft shadows, fresh tranquil mood, photorealistic fine detail');
    expect(
        light[1],
        ', harsh bright midday light, neutral white sunlight from above, strong crisp shadows, vivid true colors, intense clarity');
    expect(
        light[2],
        ', warm ember-orange sunset light raking low across the scene, long dramatic shadows, glowing rim light tracing every edge, rich warmth');
    expect(
        light[3],
        ', cold blue moonlight, deep dark shadows, silver highlights gliding over surfaces, dark tranquil nocturnal mood');
  });

  test('24h stages carry the precise variant texts as fallback', () {
    expect(k24hStages.length, 4);
    expect(k24hStages[0].promptSuffix, contains('6 am dawn'));
    expect(k24hStages[0].promptSuffix, contains('3000K rose-gold'));
    expect(k24hStages[1].promptSuffix, contains('1 pm midday'));
    expect(k24hStages[2].promptSuffix, contains('6 pm golden hour'));
    expect(k24hStages[3].promptSuffix, contains('11 pm night'));
    expect(k24hStages[3].promptSuffix, contains('7500K deep indigo'));
  });

  test('battery energy arc is the short progression from the ZIP', () {
    final energy = kStoryArcsBattery['energy']!;
    expect(energy.length, 6);
    expect(
        energy[0],
        ', charge 0 of 100: about 5 percent of the frame lit, one coin-sized dim ember of the scene own glow hue, no bloom, the rest crushed black');
    expect(
        energy[5],
        ', charge 100 of 100: the entire frame flooded at maximum output, core blown out white with the same hue at its rim, extreme bloom and star-burst flare, glowing haze everywhere, zero dark areas');
  });

  test('battery stages carry the charge-level ladder as fallback', () {
    expect(kBatteryStages.length, 6);
    expect(kBatteryStages[0].promptSuffix,
        contains('charge level 0 of 100'));
    expect(kBatteryStages[0].promptSuffix, contains('no larger than a coin'));
    expect(kBatteryStages[5].promptSuffix,
        contains('charge level 100 of 100'));
    expect(kBatteryStages[5].promptSuffix, contains('zero dark areas'));
  });

  test('dual stages keep the ZIP lock/home framing texts', () {
    expect(kDualStages.length, 2);
    expect(kDualStages[0].promptSuffix, contains('macro close-up'));
    expect(kDualStages[0].promptSuffix,
        contains('hero fills about 80 percent'));
    expect(kDualStages[1].transitionInstruction,
        contains('wide establishing view'));
    expect(kDualStages[1].transitionInstruction,
        contains('about 30 percent of the frame height'));
  });

  test('foldable prompt is the ZIP Landscape variant rules text', () {
    expect(kFoldableAdaptationPrompt, contains('(7:6, slightly wider than tall)'));
    expect(kFoldableAdaptationPrompt,
        contains('12 percent safe margin on the left and right edges'));
    expect(kFoldableAdaptationPrompt,
        contains('quiet low-detail upper third for the clock and widgets'));
    expect(kFoldableAdaptationPrompt, contains('do not crop the subject'));
    expect(kFoldableAdaptationPrompt, contains('no blurred side fills'));
    // The guard is appended by the engine, not baked into the constant.
    expect(kFoldableAdaptationPrompt, isNot(contains('no text, no letters')));
  });

  test('no arc or stage text bakes in the no-text guard', () {
    for (final stages in [
      ...kStoryArcs24h.values,
      ...kStoryArcsBattery.values,
    ]) {
      for (final s in stages) {
        expect(s, isNot(contains('no text, no letters')));
      }
    }
    for (final st in [...k24hStages, ...kBatteryStages, ...kDualStages]) {
      expect(st.promptSuffix, isNot(contains('no text, no letters')));
      expect(st.transitionInstruction, isNot(contains('no text, no letters')));
    }
  });

  test('arc smart-picks default to light and energy', () {
    expect(suggest24hArc('a mountain lake'), 'light');
    expect(suggest24hArc('a rose garden'), 'bloom');
    // NOTE: 'city street' would pick 'bloom', not 'rhythm' — the ZIP's
    // matcher is plain substring contains, and 'street' contains
    // 'tree'. Same quirk in both codebases, kept identical on purpose.
    expect(suggest24hArc('a city street'), 'bloom');
    expect(suggest24hArc('a busy city market'), 'rhythm');
    expect(suggestBatteryArc('a glowing crystal'), 'growth');
    expect(suggestBatteryArc('a phoenix'), 'awaken');
    expect(suggestBatteryArc('a neon ring'), 'energy');
  });
}
