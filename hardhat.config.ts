import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";

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
        runs: 200
      },
    }
  }
}

const config: HardhatUserConfig = {
  solidity: solidityProfiles[process.env.SOLIDITY_PROFILE || "default"] || solidityProfiles.default,
  paths: {
    sources: "./src",
    tests: "./test-ts",
    cache: "./cache_hardhat",
  },
};

export default config;
