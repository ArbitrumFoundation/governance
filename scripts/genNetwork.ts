import { execSync } from 'child_process'

import * as fs from 'fs'

function getLocalNetworksFromContainer(): any {
  const dockerNames = [
    'nitro_sequencer_1',
    'nitro-sequencer-1',
    'nitro-testnode-sequencer-1',
    'nitro-testnode_sequencer_1',
  ]
  for (const dockerName of dockerNames) {
    try {
      return JSON.parse(
        execSync(
          `docker exec ${dockerName} cat /tokenbridge-data/l1l2_network.json`
        ).toString()
      )
    } catch {
      // empty on purpose
    }
  }
  throw new Error('nitro-testnode sequencer not found')
}

async function main() {
  const data = getLocalNetworksFromContainer()
  fs.writeFileSync('./files/local/network.json', JSON.stringify(data, null, 2))
  console.log('network.json updated')
}

main().then(() => console.log('Done.'))
