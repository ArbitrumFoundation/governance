import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";

const config: HardhatUserConfig = {
  solidity: "0.8.16",
  paths: {
    sources: "./src",
    tests: "./test-ts"
  }
};

export default config;
