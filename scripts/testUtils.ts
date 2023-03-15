import { Provider } from "@ethersproject/providers";
import { BigNumber, Contract, Signer, ethers } from "ethers";
import { Interface, parseEther } from "ethers/lib/utils";
import fs from "fs";

/**
 * Simple assertion function for strings
 *
 * @param actual
 * @param expected
 * @param message
 */
export async function assertEquals(actual: string, expected: string, message: string) {
  if (actual.toLowerCase() != expected.toLowerCase()) {
    console.error("Actual: ", actual);
    console.error("Expected: ", expected);
    throw new Error(message);
  }
}

/**
 * Simple assertion function for BigNumbers
 *
 * @param actual
 * @param expected
 * @param message
 */
export async function assertNumbersEquals(actual: BigNumber, expected: BigNumber, message: string) {
  if (!actual.eq(expected)) {
    console.error("Actual: ", actual.toString());
    console.error("Expected: ", expected.toString());
    throw new Error(message);
  }
}

/**
 * Simple assertion function
 * @param condition
 * @param message
 */
export async function assert(condition: Boolean, message: string) {
  if (!condition) {
    throw new Error(message);
  }
}

/**
 * Gets the proxy owner by reading storage
 *
 * @param contractAddress
 * @param provider
 * @returns
 */
export async function getProxyOwner(contractAddress: string, provider: Provider) {
  // gets address in format like 0x000000000000000000000000a898b332e65d0cc9cb538495ff145983806d8453
  const ownerStorageValue = await provider.getStorageAt(
    contractAddress,
    "0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103"
  );

  if (!ownerStorageValue) {
    return "";
  }

  // remove execess bytes -> 0xa898b332e65d0cc9cb538495ff145983806d8453
  const formatAddress = ownerStorageValue.substring(0, 2) + ownerStorageValue.substring(26);

  // return address as checksum address -> 0xA898b332e65D0cc9CB538495FF145983806D8453
  return ethers.utils.getAddress(formatAddress);
}

export type Recipients = { readonly [key: string]: BigNumber };

export const loadRecipients = (fileLocation: string): Recipients => {
  const fileContents = fs.readFileSync(fileLocation).toString();
  const jsonFile = JSON.parse(fileContents);
  const addresses = Object.keys(jsonFile);
  const recipients: { [key: string]: BigNumber } = {};

  for (const addr of addresses) {
    // the token has 18 decimals, like ether, so we can use parseEther
    recipients[addr.toLowerCase()] = parseEther(jsonFile[addr]);

    if (recipients[addr.toLowerCase()].lt(parseEther("1"))) {
      throw new Error(
        `Unexpected token count less than 1: ${recipients[addr.toLowerCase()].toString()}`
      );
    }
  }

  return recipients;
};

export type ClaimRecipients = { [addr: string]: { points: number } };

/**
 * Map points to claimable token amount
 * @param point
 */
export function pointToTokenAmount(point: number): number {
  switch (point) {
    case 3: {
      return 1250;
    }
    case 4: {
      return 1750;
    }
    case 5: {
      return 2250;
    }
    case 6: {
      return 3250;
    }
    case 7: {
      return 3750;
    }
    case 8: {
      return 4000;
    }
    case 9: {
      return 6250;
    }
    case 10: {
      return 6750;
    }
    case 11: {
      return 7250;
    }
    case 12:
    case 13:
    case 14:
    case 15: {
      return 10250;
    }

    default: {
      throw new Error("Incorrect number of points " + point);
    }
  }
}

export type TypeChainContractFactory<TContract extends Contract> = {
  deploy(...args: Array<any>): Promise<TContract>;
};

export type TypeChainContractFactoryStatic<TContract extends Contract> = {
  connect(address: string, signerOrProvider: Provider | Signer): TContract;
  createInterface(): Interface;
  new (signer: Signer): TypeChainContractFactory<TContract>;
};

export type StringProps<T> = {
  [k in keyof T as T[k] extends string | undefined ? k : never]: T[k];
};
