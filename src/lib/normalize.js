const prefixFactors = Object.freeze({
  '': 1,
  k: 1e3,
  M: 1e6,
  m: 1e-3,
  'µ': 1e-6,
  u: 1e-6,
  n: 1e-9,
  p: 1e-12,
});

/**
 * Normalize an engineering number to its base-unit value.
 * Unit symbols are stripped, not checked for dimensional compatibility.
 * @param {string|number} input Numeric input, optionally with an SI prefix/unit.
 * @returns {number|null} A finite value, or null for invalid input.
 */
export function normalize(input) {
  if (typeof input === 'number') return Number.isFinite(input) ? input : null;
  if (typeof input !== 'string') return null;

  const compact = input.replace(/\s/gu, '').replaceAll(',', '.');
  const match = /^([+-]?(?:\d+(?:\.\d+)?|\.\d+))([kMmµunp]?)([ΩVAWFH]?)$/u.exec(compact);
  if (!match) return null;

  const value = Number(match[1]) * prefixFactors[match[2]];
  return Number.isFinite(value) ? value : null;
}

/**
 * Compare normalized values using a relative tolerance (0.01 means 1%).
 * This pure helper performs no submission, answer lookup or gameplay writes.
 * @param {string|number} input Candidate numeric input.
 * @param {string|number} expected Reference value supplied by the caller.
 * @param {number} [tolerance=0.01] Nonnegative finite relative tolerance.
 * @returns {boolean} Whether both inputs are valid and within tolerance.
 */
export function isWithinRelativeTolerance(input, expected, tolerance = 0.01) {
  if (!Number.isFinite(tolerance) || tolerance < 0) return false;
  const actualValue = normalize(input);
  const expectedValue = normalize(expected);
  if (actualValue === null || expectedValue === null) return false;
  if (tolerance === 0 || expectedValue === 0) return actualValue === expectedValue;

  // Scale before subtraction/multiplication to avoid overflowing finite inputs.
  const scale = Math.max(Math.abs(actualValue), Math.abs(expectedValue));
  const difference = Math.abs(actualValue / scale - expectedValue / scale);
  const allowance = Math.abs(expectedValue / scale) * tolerance;
  // Protect inclusive decimal boundaries from binary floating-point roundoff.
  return difference <= allowance + Number.EPSILON;
}
