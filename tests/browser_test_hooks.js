'use strict';

const assert = require('node:assert/strict');

const mobileTestHooks = `
globalThis.__PocketTrackerTestHooks = Object.freeze({
  projectIO: Object.freeze({
    key: projectStoreKey,
    commands: projectCommands,
    crc16,
    envelopeValid,
    envelopeRecord,
    parseProjectJson,
    projectJson,
    materializedBank,
    p8Audio,
    parseP8Audio,
    storeLastKnownGood,
    loadLastKnownGood,
    frameValid,
    writeFrame,
  }),
  library: Object.freeze({
    key: projectLibraryKey,
    maxProjects: projectLibraryMaxProjects,
    maxRevisions: projectLibraryMaxRevisions,
    maxChars: projectLibraryMaxChars,
    emptyProjectLibrary,
    parseProjectLibrary,
    loadProjectLibrary,
    storeProjectLibrary,
    migrateProjectLibrary,
    addLibraryProject,
    addLibraryRevision,
    stageLibraryRevision,
    deleteLibraryRevision,
    confirmLibraryDelete,
    libraryDeleteFeedback,
    resetProjectLibrary,
    projectTransferActive,
  }),
  fileIO: Object.freeze({importProjectJson, importProjectP8, exportStoredFile}),
});
`;

function withMobileTestHooks(source) {
  assert.equal(typeof source, 'string');
  return source + mobileTestHooks;
}

function withHelpTestHooks(source) {
  assert.equal(typeof source, 'string');
  const marker = '\n})();\n';
  const index = source.lastIndexOf(marker);
  assert.equal(index + marker.length, source.length, 'help test bridge requires the final IIFE marker');
  return `${source.slice(0, index)}

  globalThis.__PocketTrackerTestHooks = Object.freeze({
    help: Object.freeze({open: openHelp, close: closeHelp, isOpen: () => active}),
  });
})();
`;
}

module.exports = {withMobileTestHooks, withHelpTestHooks};
