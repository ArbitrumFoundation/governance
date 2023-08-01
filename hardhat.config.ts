import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-foundry";

const solidityProfiles = {
  default: {
    version: "0.8.16",
    settings: {
      optimizer: {
        enabled: true,
        runs: 20000
      },
    }
  },
  sec_council_mgmt: {
    version: "0.8.16",
    settings: {
      optimizer: {
        enabled: true,
        runs: 1900
      },
    }
  }
}

const config: HardhatUserConfig = {
  solidity: solidityProfiles[process.env.FOUNDRY_PROFILE || "default"] || solidityProfiles.default,
  paths: {
    sources: "./src",
    tests: "./test-ts",
    cache: "./cache_hardhat",
  },
};

export default config;
