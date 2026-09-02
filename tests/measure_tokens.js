'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {spawnSync} = require('node:child_process');

const root = path.resolve(__dirname, '..');
const pico8 = process.env.PICO8_BIN || '/home/nick/Development/pico8/pico-8/pico8';
const budgetPath = path.join(__dirname, 'size_budget.p8');
const probeStatements = 512;
const calibratedProbeTokens = 1024;
const addedProbeTokens = probeStatements * 3;
const temporaryName = `.token-measure-${process.pid}-${Date.now()}.p8`;
const temporaryPath = path.join(__dirname, temporaryName);

const budget = fs.readFileSync(budgetPath, 'utf8');
const insertion = `${'size_probe+=1;'.repeat(probeStatements)}\n`;
assert.equal((budget.match(/size_probe\+=1;/g) || []).length, 337,
  'the 1,024-token calibrated probe changed; recalibrate before measuring');
assert.equal((budget.match(/^ flip\(\)$/gm) || []).length, 1,
  'the calibrated budget-cart insertion point changed');
const measured = budget.replace(' flip()', `${insertion} flip()`);

try {
  fs.writeFileSync(temporaryPath, measured);
  const result = spawnSync(pico8, ['-x', `tests/${temporaryName}`], {
    cwd: root,
    encoding: 'utf8',
    env: {...process.env, SDL_VIDEODRIVER: 'dummy', SDL_AUDIODRIVER: 'dummy'},
    timeout: 5000,
  });
  const output = `${result.stdout || ''}${result.stderr || ''}`;
  const match = /([0-9]+)\s*\/\s*8192 tokens/.exec(output);
  assert.ok(match, `PICO-8 did not report the overflow token total:\n${output}`);

  const overflowTotal = Number(match[1]);
  const production = overflowTotal - calibratedProbeTokens - addedProbeTokens;
  assert.ok(production > 0 && production <= 7082,
    `production token count ${production} exceeds the campaign baseline`);
  console.log(JSON.stringify({
    production,
    overflowTotal,
    calibratedProbeTokens,
    addedProbeStatements: probeStatements,
    addedProbeTokens,
  }));
} finally {
  fs.rmSync(temporaryPath, {force: true});
}
