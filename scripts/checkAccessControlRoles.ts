import { IAccessControlUpgradeable__factory } from "../typechain-types";
import { keccak256, toUtf8Bytes } from "ethers/lib/utils";
import { Provider, JsonRpcProvider } from "@ethersproject/providers";

import { RoleGrantedEventObject } from "../typechain-types/@openzeppelin/contracts-upgradeable/access/IAccessControlUpgradeable";

interface RolesToRolePreimages {
  [key: string]: string;
}

interface RolesToAccounts {
  [key: string]: Set<string>;
}

const rolesPreimages = [
  "TIMELOCK_ADMIN_ROLE",
  "PROPOSER_ROLE",
  "EXECUTOR_ROLE",
  "CANCELLER_ROLE",
  "ADMIN_ROLE",
  "COHORT_REPLACER",
  "MEMBER_ADDER",
  "MEMBER_REPLACER",
  "MEMBER_ROTATOR",
  "MEMBER_REMOVER",
];
const rolesToRolePreimages: RolesToRolePreimages = {};
rolesPreimages.forEach((roleStr: string) => {
  rolesToRolePreimages[keccak256(toUtf8Bytes(roleStr))] = roleStr;
});

export const getCurrentRoles = async (
  rpcProvider: Provider,
  contractAddr: string,
  displayName: string,
  fromBlock = 0,
  verbose = true
) => {
  const network = await rpcProvider.getNetwork();
  if (verbose) {
    console.log(`Checking roles for ${contractAddr} "${displayName}" on chain ${network.chainId}`);
  }

  const accessControlContract = IAccessControlUpgradeable__factory.connect(
    contractAddr,
    rpcProvider
  );
  const filterTopics = accessControlContract.interface.encodeFilterTopics("RoleGranted", []);

  const roleGrantedLogsRaw = await rpcProvider.getLogs({
    fromBlock,
    topics: filterTopics,
    address: contractAddr,
  });

  const roleGrantedLogs = roleGrantedLogsRaw.map((log) => {
    const parsedLog = accessControlContract.interface.parseLog(log);
    return parsedLog.args as unknown as RoleGrantedEventObject;
  });

  const rolesToAccounts: RolesToAccounts = {};
  for (let roleGrantedLog of roleGrantedLogs) {
    const { role, account } = roleGrantedLog;

    if (!(await accessControlContract.hasRole(role, account))) {
      continue;
    }

    if (rolesToAccounts[role]) {
      rolesToAccounts[role].add(account);
    } else {
      rolesToAccounts[role] = new Set([account]);
    }
  }
  if (verbose) {
    for (let roleHash of Object.keys(rolesToAccounts)) {
      const roleToDisplay = rolesToRolePreimages[roleHash]
        ? rolesToRolePreimages[roleHash]
        : roleHash;
      console.log("");
      console.log(`Accounts with '${roleToDisplay}':`);
      for (let account of rolesToAccounts[roleHash]) {
        console.log(account);
      }
    }
    console.log("");
    console.log("");
  }
  return rolesToAccounts;
};
