import { writeFile } from 'node:fs/promises';

export async function attachMeasurements(testInfo, name, measurements) {
  const path = testInfo.outputPath(`${name}.json`);
  await writeFile(path, JSON.stringify(measurements, null, 2));
  await testInfo.attach(name, { path, contentType: 'application/json' });
}
