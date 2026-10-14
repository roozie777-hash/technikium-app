import assert from 'node:assert/strict';
import test from 'node:test';
import { normalize, isWithinRelativeTolerance } from '../src/lib/normalize.js';

// These vectors are the contract for the future database implementation too.
const normalizationCases = [
  ['4,7', 4.7], ['4.7', 4.7], ['4,7k', 4700], ['4.7 kΩ', 4700],
  ['4700', 4700], ['4700 Ω', 4700], ['2M', 2000000], ['2 MΩ', 2000000],
  ['2m', 0.002], ['2 mA', 0.002], ['1µ', 0.000001], ['1 µA', 0.000001],
  ['1uA', 0.000001], ['1nF', 0.000000001], ['1pF', 0.000000000001],
  ['12 V', 12], ['3 A', 3], ['5Ω', 5], ['2W', 2], ['3F', 3], ['4H', 4],
  ['\t4,7\u00a0kΩ\n', 4700], ['-2,5mV', -0.0025], ['+12V', 12],
  ['0', 0], ['0µA', 0], ['.5V', 0.5], [',5A', 0.5], [4.7, 4.7],
];

for (const [input, expected] of normalizationCases) {
  test(`normalize ${JSON.stringify(input)} = ${expected}`, () => {
    assert.equal(normalize(input), expected);
  });
}

for (const input of ['', ' ', 'abc', '4,7,2', '4.7.2', '4kMΩ', '4ΩV',
  '4Vjunk', '4 KΩ', '1e3', 'Infinity', 'NaN', '0x10', null, undefined,
  true, {}, [], NaN, Infinity, -Infinity]) {
  test(`normalize rejects ${String(input)} (${typeof input})`, () => {
    assert.equal(normalize(input), null);
  });
}

test('mega and milli remain case-sensitive and differ by a factor of one billion', () => {
  assert.equal(normalize('2M') / normalize('2m'), 1000000000);
});

const toleranceCases = [
  ['equivalent units and comma', '4,7kΩ', '4700', undefined, true],
  ['default upper boundary', '101 V', '100', undefined, true],
  ['default lower boundary', '99', '100 V', undefined, true],
  ['above default upper boundary', '101.001', '100', undefined, false],
  ['below default lower boundary', '98.999', '100', undefined, false],
  ['decimal upper boundary', '4.747', '4.7', 0.01, true],
  ['decimal lower boundary', '4.653', '4.7', 0.01, true],
  ['decimal outside boundary', '4.6529', '4.7', 0.01, false],
  ['custom two percent boundary', '102', '100', 0.02, true],
  ['custom tolerance exceeded', '102.001', '100', 0.02, false],
  ['milliampere conversion', '2,01mA', '0.002', 0.01, true],
  ['microampere conversion', '1µA', '0.000001', 0, true],
  ['negative reference within boundary', '-99', '-100', 0.01, true],
  ['negative reference outside boundary', '-98', '-100', 0.01, false],
  ['zero reference exact match', '0 V', '0', 0.01, true],
  ['zero reference has no absolute tolerance', '0.000001', '0', 0.01, false],
  ['zero tolerance exact match', '2mA', '0.002', 0, true],
  ['zero tolerance rejects nearby value', 1 + Number.EPSILON, 1, 0, false],
  ['invalid candidate', 'wrong', '100', 0.01, false],
  ['invalid reference', '100', '', 0.01, false],
  ['large finite numbers outside tolerance without overflow', -1e308, 1e308, 1.9, false],
  ['large finite numbers on boundary without overflow', -1e308, 1e308, 2, true],
];

for (const [name, input, expected, tolerance, result] of toleranceCases) {
  test(`relative tolerance: ${name}`, () => {
    assert.equal(isWithinRelativeTolerance(input, expected, tolerance), result);
  });
}

for (const tolerance of [-0.01, NaN, Infinity, '0.01', null]) {
  test(`rejects invalid tolerance ${String(tolerance)}`, () => {
    assert.equal(isWithinRelativeTolerance('100', '100', tolerance), false);
  });
}
