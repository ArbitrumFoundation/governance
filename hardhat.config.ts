import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-foundry";
import dotenv from "dotenv";
dotenv.config();
// when changing optimizer settings, make sure to also change settings in foundry.toml
const solidityProfiles = {
  default: {
    compilers: [
      {
        version: "0.8.16",
        settings: {
          optimizer: {
            enabled: true,
            runs: 20000,
          },
        },
      },
      {
        version: "0.8.26",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
  },
  sec_council_mgmt: {
    compilers: [
      {
        version: "0.8.16",
        settings: {
          optimizer: {
            enabled: true,
            runs: 750,
          },
        },
      },
      {
        version: "0.8.26",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
  },
};

const solidity =
  solidityProfiles[process.env.FOUNDRY_PROFILE || "default"] || solidityProfiles.default;
console.log("Compiling with soldity profile:", solidity);

const config: HardhatUserConfig = {
  solidity,
  paths: {
    sources: "./src",
    tests: "./test-ts",
    cache: "./cache_hardhat",
  },
};

export default config;
