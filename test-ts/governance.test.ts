import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect, util } from "chai";
import { ethers } from "hardhat";
import {
  L1GovernanceFactory__factory,
  L2ArbitrumToken,
  L2ArbitrumToken__factory,
  L2GovernanceFactory__factory,
  ProxyAdmin__factory,
  TransparentUpgradeableProxy__factory,
} from "../typechain-types";
import { fundL1, fundL2, testSetup } from "./testSetup";
import { JsonRpcProvider } from "@ethersproject/providers";
import { Interface } from "@ethersproject/abi";
import { BigNumber } from "ethers";
import { parseEther } from "ethers/lib/utils";
// CHRIS: TODO: move typechain types to the right place?

describe("Lock", function () {
  // // We define a fixture to reuse the same setup in every test.
  // // We use loadFixture to run this setup once, snapshot that state,
  // // and reset Hardhat Network to that snapshot in every test.
  // async function deployOneYearLockFixture() {
  //   const ONE_YEAR_IN_SECS = 365 * 24 * 60 * 60;
  //   const ONE_GWEI = 1_000_000_000;

  //   const lockedAmount = ONE_GWEI;
  //   const unlockTime = (await time.latest()) + ONE_YEAR_IN_SECS;

  //   // Contracts are deployed using the first signer/account by default
  //   const [owner, otherAccount] = await ethers.getSigners();

  //   const Lock = await ethers.getContractFactory("Lock");
  //   const lock = await Lock.deploy(unlockTime, { value: lockedAmount });

  //   return { lock, unlockTime, lockedAmount, owner, otherAccount };
  // }

  // describe("Deployment", function () {
  it("Round trip test", async function () {
    const { l1Signer, l2Signer } = await testSetup();
    // CHRIS: TODO: move these into test setup
    await fundL1(l1Signer, parseEther("1"))

    await fundL2(l2Signer, parseEther("1"))

    

    // const signer = (await ethers.getSigners())[0];

    // const l2ArbTokenFac = new L2ArbitrumToken__factory(signer)
    // const l2ArbTokenImpl = await l2ArbTokenFac.deploy();
    // const proxyAdmin = await new ProxyAdmin__factory(signer).deploy();
    // const l2ArbTokenProxy = (await new TransparentUpgradeableProxy__factory(
    //   signer
    // ).deploy(
    //   l2ArbTokenImpl.address,
    //   proxyAdmin.address,
    //   "0x"
    // ))

    // const l2ArbToken = l2ArbTokenFac.attach(l2ArbTokenProxy.address)

    // const l1Address = "0x0000000000000000000000000000000000000001";
    // const owner = "0x0000000000000000000000000000000000000002";
    // const init = await l2ArbToken.initialize(
    //   l1Address,
    //   ethers.utils.parseUnits("10000000000", "ether"),
    //   owner
    // );
    // await init.wait();

    // uint256 initialSupply = 10 * 10 ** 9;
    // uint256 l1TimelockDelay = 10;
    // uint256 l2TimelockDelay = 15;
    // address l1TokenAddr = address(1);

    const initialSupply = parseEther("1");
    const l1TimeLockDelay = 10;
    const l2TimeLockDelay = 15;

    // deploy all the governance
    // new L2GovernanceFactory__factory(
    // )

    const l1GovernanceFac = await new L1GovernanceFactory__factory(
      l1Signer
    ).deploy();


    // const l2GovernanceFac = await new L2GovernanceFactory__factory(
    //   l2Signer
    // ).deploy();

    // const l1Governance = await l1GovernanceFac.deploy();
    // const deployReceipt = await (
    //   await l1Governance.deploy(l1TimeLockDelay)
    // ).wait();

    // console.log(deployReceipt)
  });

  //   it("Should set the right owner", async function () {
  //     const { lock, owner } = await loadFixture(deployOneYearLockFixture);

  //     expect(await lock.owner()).to.equal(owner.address);
  //   });

  //   it("Should receive and store the funds to lock", async function () {
  //     const { lock, lockedAmount } = await loadFixture(
  //       deployOneYearLockFixture
  //     );

  //     expect(await ethers.provider.getBalance(lock.address)).to.equal(
  //       lockedAmount
  //     );
  //   });

  //   it("Should fail if the unlockTime is not in the future", async function () {
  //     // We don't use the fixture here because we want a different deployment
  //     const latestTime = await time.latest();
  //     const Lock = await ethers.getContractFactory("Lock");
  //     await expect(Lock.deploy(latestTime, { value: 1 })).to.be.revertedWith(
  //       "Unlock time should be in the future"
  //     );
  //   });
  // });

  // describe("Withdrawals", function () {
  //   describe("Validations", function () {
  //     it("Should revert with the right error if called too soon", async function () {
  //       const { lock } = await loadFixture(deployOneYearLockFixture);

  //       await expect(lock.withdraw()).to.be.revertedWith(
  //         "You can't withdraw yet"
  //       );
  //     });

  //     it("Should revert with the right error if called from another account", async function () {
  //       const { lock, unlockTime, otherAccount } = await loadFixture(
  //         deployOneYearLockFixture
  //       );

  //       // We can increase the time in Hardhat Network
  //       await time.increaseTo(unlockTime);

  //       // We use lock.connect() to send a transaction from another account
  //       await expect(lock.connect(otherAccount).withdraw()).to.be.revertedWith(
  //         "You aren't the owner"
  //       );
  //     });

  //     it("Shouldn't fail if the unlockTime has arrived and the owner calls it", async function () {
  //       const { lock, unlockTime } = await loadFixture(
  //         deployOneYearLockFixture
  //       );

  //       // Transactions are sent using the first signer by default
  //       await time.increaseTo(unlockTime);

  //       await expect(lock.withdraw()).not.to.be.reverted;
  //     });
  //   });

  //   describe("Events", function () {
  //     it("Should emit an event on withdrawals", async function () {
  //       const { lock, unlockTime, lockedAmount } = await loadFixture(
  //         deployOneYearLockFixture
  //       );

  //       await time.increaseTo(unlockTime);

  //       await expect(lock.withdraw())
  //         .to.emit(lock, "Withdrawal")
  //         .withArgs(lockedAmount, anyValue); // We accept any value as `when` arg
  //     });
  //   });

  //   describe("Transfers", function () {
  //     it("Should transfer the funds to the owner", async function () {
  //       const { lock, unlockTime, lockedAmount, owner } = await loadFixture(
  //         deployOneYearLockFixture
  //       );

  //       await time.increaseTo(unlockTime);

  //       await expect(lock.withdraw()).to.changeEtherBalances(
  //         [owner, lock],
  //         [lockedAmount, -lockedAmount]
  //       );
  //     });
  //   });
  // });
});
