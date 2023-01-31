import { BigNumber, Wallet } from "ethers";
import {
  formatBytes32String,
  hexlify,
  keccak256,
  zeroPad,
} from "ethers/lib/utils";
import * as fs from "fs";

// example
// "0x4fbede53b59d1a2ab85f785ad76e1dcd66a1546a": {
//     "points": 15,
//     "meets_criteria_2_1": 1,
//     "meets_criteria_2_2_a": 1,
//     "meets_criteria_2_2_b": 1,
//     "meets_criteria_2_2_c": 1,
//     "meets_criteria_2_3_a": 1,
//     "meets_criteria_2_3_b": 1,
//     "meets_criteria_2_3_c": 1,
//     "meets_criteria_2_3_d": 1,
//     "meets_criteria_2_4_a": 1,
//     "meets_criteria_2_4_b": 1,
//     "meets_criteria_2_4_c": 1,
//     "meets_criteria_2_6": 0, // bad
//     "meets_criteria_2_7": 0, // bad
//     "meets_criteria_2_8": 0, // bad
//     "meets_criteria_4_1": 1,
//     "meets_criteria_4_2": 1,
//     "meets_criteria_4_3": 1,
//     "meets_criteria_11_1": 1,
//     "meets_criteria_11_2": 1,
//     "meets_criteria_11_3": 0,
//     "meets_criteria_11_4": 0
//   },

const makeRandomCriteria = () => {
  const zeroOrOne = () => {
    return Math.round(Math.random());
  };

  // at least one criteria must be met
  const baseCriteriaCount = 6;
  // index and count
  const baseCriteria: { [key: number]: number } = {
    0: 1,
    1: 3,
    4: 4,
    8: 3,
    14: 3,
    17: 4,
  };

  const guaranteedMet = Math.floor(Math.random() * baseCriteriaCount);
  const getCriteriaIndex = (baseIndex: number) => {
    return Number.parseInt(Object.keys(baseCriteria)[baseIndex]);
  };

  const criteria: { [key: number]: number } = {};
  const guaranteedIndex = getCriteriaIndex(guaranteedMet);
  criteria[guaranteedIndex] = 1;

  const criteriaIndices = Object.keys(baseCriteria);

  // populate the remaining criteria
  let pointsSoFar = 0;
  for (let index = 0; index < criteriaIndices.length; index++) {
    const criteriaIndex = getCriteriaIndex(index);

    // set random and dependent items
    let currentVal = criteria[criteriaIndex] || zeroOrOne();

    for (
      let dependency = 0;
      dependency < baseCriteria[getCriteriaIndex(index)];
      dependency++
    ) {
      pointsSoFar += currentVal;
      criteria[criteriaIndex + dependency] = currentVal;

      // set a new val if we have dependencies
      if (currentVal === 1) {
        currentVal = zeroOrOne();
      }
    }
  }

  // now set some negative points
  let currentBadVal = zeroOrOne();
  let badPointsSoFar = 0;
  for (let index = 11; index < 14; index++) {
    badPointsSoFar += currentBadVal;
    // dont allow bad points to exceed normal points
    if (badPointsSoFar > pointsSoFar - 1) currentBadVal = 0;

    criteria[index] = currentBadVal;

    if (currentBadVal === 1) {
      currentBadVal = zeroOrOne();
    }
  }

  return {
    meets_criteria_2_1: criteria[0],
    meets_criteria_2_2_a: criteria[1],
    meets_criteria_2_2_b: criteria[2],
    meets_criteria_2_2_c: criteria[3],
    meets_criteria_2_3_a: criteria[4],
    meets_criteria_2_3_b: criteria[5],
    meets_criteria_2_3_c: criteria[6],
    meets_criteria_2_3_d: criteria[7],
    meets_criteria_2_4_a: criteria[8],
    meets_criteria_2_4_b: criteria[9],
    meets_criteria_2_4_c: criteria[10],
    meets_criteria_2_6: criteria[11],
    meets_criteria_2_7: criteria[12],
    meets_criteria_2_8: criteria[13],
    meets_criteria_4_1: criteria[14],
    meets_criteria_4_2: criteria[15],
    meets_criteria_4_3: criteria[16],
    meets_criteria_11_1: criteria[17],
    meets_criteria_11_2: criteria[18],
    meets_criteria_11_3: criteria[19],
    meets_criteria_11_4: criteria[20],
  };
};

const calculatePoints = (criteria: ReturnType<typeof makeRandomCriteria>) => {
  let badPoints = 0;
  let normalPoints = 0;
  let novaPoints = 0;
  for (const key in Object.keys(criteria)) {
    const sKey = Object.keys(criteria)[key] as keyof typeof criteria;
    const val = criteria[sKey];
    switch (sKey) {
      case "meets_criteria_2_6":
      case "meets_criteria_2_7":
      case "meets_criteria_2_8": {
        badPoints += val;
        break;
      }
      case "meets_criteria_11_1":
      case "meets_criteria_11_2":
      case "meets_criteria_11_3":
      case "meets_criteria_11_4": {
        novaPoints += val;
        break;
      }
      default:
        normalPoints += val;
    }
  }

  normalPoints -= badPoints;

  const points = Math.max(
    normalPoints + (novaPoints > 0 ? 1 : 0),
    Math.min(novaPoints + normalPoints, 4)
  );

  // points should be in interval [3,15]
  return Math.min(Math.max(points, 3), 15);
};

const toPrivKey = (seed: BigNumber) => {
  return keccak256(hexlify(zeroPad(seed.toHexString(), 32)));
};

const run = (
  hardcodedAddress: string[],
  randomCount: number,
  outputLocation: string
) => {
  let recipients: { [key: string]: any } = {};

  for (const addr of hardcodedAddress) {
    const c = makeRandomCriteria();
    const p = calculatePoints(c);

    recipients[addr] = {
      points: p,
      ...c,
    };
  }

  let privKeyNum = BigNumber.from(0);
  for (let index = 0; index < randomCount; index++) {
    const c = makeRandomCriteria();
    const p = calculatePoints(c);

    const privKey = toPrivKey(privKeyNum);
    const wall = new Wallet(privKey);
    const addr = wall.address;

    recipients[addr] = {
      points: p,
      ...c,
      privKey,
    };

    privKeyNum = privKeyNum.add(1);

    if (index % 1000 == 0) console.log(`Created ${index} recipients`);
  }

  fs.writeFileSync(outputLocation, JSON.stringify(recipients, null, 2));
};

const myAddresses: string[] = [];
run(myAddresses, 300000, "testRecipients.json");
