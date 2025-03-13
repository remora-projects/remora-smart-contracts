const {
  loadFixture,
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { deployContractsAndSetVariables } = require("./helpers/setup-contracts");
const { getSelector } = require("./helpers/access-manager-setup");
const { ethers, upgrades } = require("hardhat");
const { expect } = require("chai");
const { AbiCoder } = require("ethers");

describe("Access Manager Tests", function () {
  async function setUpAccessManagerTests() {
    return await deployContractsAndSetVariables(10, 0, 0, 0, true);
  }

  it("Should successfully upgrade Access Manager", async function () {
    const { owner, custodian, accessmanager } = await loadFixture(
      setUpAccessManagerTests
    );

    const upgrader_id = 1;
    await accessmanager.labelRole(upgrader_id, "UPGRADER");
    const selectors = [getSelector("upgradeToAndCall(address,bytes)")];
    await accessmanager.setTargetFunctionRole(
      accessmanager.target,
      selectors,
      upgrader_id
    );

    const RemoraManagerV2 = await ethers.getContractFactory("RemoraManagerV2");
    await accessmanager.grantRole(0, custodian, 0);
    await accessmanager.renounceRole(0, owner.address);

    await expect(
      upgrades.upgradeProxy(accessmanager.target, RemoraManagerV2)
    ).to.be.revertedWith("Unauthorized upgrade");

    await accessmanager.connect(custodian).grantRole(0, owner, 0); // grant role to allow upgrade

    const accessmanagerV2 = await upgrades.upgradeProxy(
      accessmanager.target,
      RemoraManagerV2
    );

    expect(await accessmanagerV2.version()).to.equal(2);
  });

  // it("Should successfully upgrade Access Manager, with delay", async function () {
  //   const { owner, accessmanager } = await loadFixture(setUpAccessManagerTests);

  //   const upgrader_id = 1;
  //   await accessmanager.labelRole(upgrader_id, "UPGRADER");
  //   const selector = getSelector("upgradeToAndCall(address,bytes)");
  //   await accessmanager.setTargetFunctionRole(
  //     accessmanager.target,
  //     [selector],
  //     upgrader_id
  //   );

  //   //CALL SCHEDULE(ADDRESS TARGET, BYTES DATA, UINT WHEN)
  //   //Then call execute(addresss target, bytes data);

  //   const RemoraManagerV2 = await ethers.getContractFactory("RemoraManagerV2");

  //   await expect(
  //     upgrades.upgradeProxy(accessmanager.target, RemoraManagerV2)
  //   ).to.be.revertedWith("Unauthorized Upgrade");

  //   await accessmanager.grantRole(upgrader_id, owner, 1); // grant role to allow upgrade, 1 second delay

  //   const newImplementation = await upgrades.deployImplementation(RemoraManagerV2, {
  //     kind: "uups",
  //   });

  //   const encodedArgs =

  //   await accessmanager.schedule(accessmanager.target);

  //   // const accessmanagerV2 = await upgrades.upgradeProxy(
  //   //   accessmanager.target,
  //   //   RemoraManagerV2
  //   // );

  //   expect(await accessmanagerV2.version()).to.equal(2);
  // });
});
