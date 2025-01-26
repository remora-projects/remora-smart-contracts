const {
  loadFixture,
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { deployContractsAndSetVariables } = require("../helpers/SetUpContracts");
const { CUSTODIAN_ID } = require("../helpers/AccessManagerSetUp");
const { ethers, upgrades } = require("hardhat");
const { expect } = require("chai");

describe("RemoraRWAToken", function () {
  describe("RWAToken Tests", function () {
    it("Should pause halting transfer, then unpause", async function () {
      const {
        owner,
        investor1,
        custodian,
        facilitator,
        state_changer,
        remoratoken,
        allowlist,
      } = await loadFixture(deployContractsAndSetVariables);

      await allowlist.connect(custodian).allowUser(investor1.address);
      await remoratoken.approve(facilitator.address, 10);
      await remoratoken
        .connect(facilitator)
        .transferFrom(owner.address, investor1.address, 10);

      await remoratoken.connect(investor1).approve(facilitator.address, 10);
      await remoratoken.connect(state_changer).pause();

      await expect(
        remoratoken
          .connect(facilitator)
          .transferFrom(investor1.address, owner.address, 10)
      ).to.be.revertedWithCustomError(remoratoken, "EnforcedPause");

      await remoratoken.connect(state_changer).unpause();

      await expect(
        remoratoken
          .connect(facilitator)
          .transferFrom(investor1.address, owner.address, 10)
      ).to.changeTokenBalances(remoratoken, [investor1, owner], [-10, +10]);
    });

    it("Should revert due to transfer to unregistered user, then allow after registering", async function () {
      const {
        owner,
        investor1,
        custodian,
        facilitator,
        remoratoken,
        allowlist,
      } = await loadFixture(deployContractsAndSetVariables);

      await remoratoken.approve(facilitator.address, 10);

      await expect(
        remoratoken
          .connect(facilitator)
          .transferFrom(owner.address, investor1.address, 10)
      ).to.be.revertedWithCustomError(allowlist, "UserNotRegistered");

      await allowlist.connect(custodian).allowUser(investor1.address);

      await expect(
        remoratoken
          .connect(facilitator)
          .transferFrom(owner.address, investor1.address, 10)
      ).to.changeTokenBalances(remoratoken, [investor1, owner], [+10, -10]);
    });

    it("Should revert due to restricted transfer", async function () {
      const { investor1, custodian, remoratoken, allowlist } =
        await loadFixture(deployContractsAndSetVariables);

      await allowlist.connect(custodian).allowUser(investor1.address);
      await expect(
        remoratoken.transfer(investor1.address, 10)
      ).to.be.revertedWithCustomError(remoratoken, "AccessManagedUnauthorized");
    });

    it("Should properly upgrade RWAToken and Allowlist, while keeping all data + some restrictions", async function () {
      //removed restriction on transfer, other restrictions should be retained
      const {
        owner,
        accessmanager,
        investor1,
        investor2,
        facilitator,
        custodian,
        remoratoken,
        allowlist,
      } = await loadFixture(deployContractsAndSetVariables);

      await allowlist.connect(custodian).allowUser(investor1.address);
      await remoratoken.approve(facilitator.address, 5);
      await remoratoken
        .connect(facilitator)
        .transferFrom(owner.address, investor1.address, 5);

      const RemoraAllowListV2 = await ethers.getContractFactory(
        "RemoraAllowlistV2"
      );

      await expect(
        upgrades.upgradeProxy(allowlist.target, RemoraAllowListV2)
      ).to.be.revertedWithCustomError(allowlist, "AccessManagedUnauthorized");

      await accessmanager.grantRole(CUSTODIAN_ID, owner, 0); // grant role to owner so can upgrade

      const allowlistV2 = await upgrades.upgradeProxy(
        allowlist.target,
        RemoraAllowListV2
      );

      expect(await allowlistV2.version()).to.equal(2);

      const RemoraRWATokenV2 = await ethers.getContractFactory(
        "RemoraRWATokenV2"
      );
      const remoratokenV2 = await upgrades.upgradeProxy(
        remoratoken.target,
        RemoraRWATokenV2
      );

      expect(await remoratokenV2.version()).to.equal(2);

      await expect(
        remoratokenV2.transfer(investor2.address, 5)
      ).to.be.revertedWithCustomError(allowlistV2, "UserNotRegistered");

      await expect(
        remoratokenV2.transfer(investor1.address, 5)
      ).to.changeTokenBalances(remoratokenV2, [owner, investor1], [-5, +5]);
    });
  });

  describe("Burnable Tests", function () {
    it("Should revert due to burning disabled, then burn tokens successfully after enable", async function () {
      const { owner, state_changer, remoratoken } = await loadFixture(
        deployContractsAndSetVariables
      );

      await expect(remoratoken.burn(10)).to.be.revertedWithCustomError(
        remoratoken,
        "BurningNotEnabled"
      );

      await remoratoken.connect(state_changer).enableBurning();

      await expect(remoratoken.burn(10)).to.changeTokenBalance(
        remoratoken,
        owner,
        -10
      );
    });

    it("Should not allow restricted account to use burnFrom, then successfully allow facilitator to burnFrom", async function () {
      const { owner, state_changer, facilitator, remoratoken } =
        await loadFixture(deployContractsAndSetVariables);

      await remoratoken.approve(facilitator.address, 10);
      await remoratoken.approve(state_changer.address, 10);
      await expect(
        remoratoken.connect(facilitator).burnFrom(owner.address, 10)
      ).to.be.revertedWithCustomError(remoratoken, "BurningNotEnabled");

      await remoratoken.connect(state_changer).enableBurning();

      await expect(
        remoratoken.connect(state_changer).burnFrom(owner.address, 10)
      ).to.be.revertedWithCustomError(remoratoken, "AccessManagedUnauthorized");

      await expect(
        remoratoken.connect(facilitator).burnFrom(owner.address, 10)
      ).to.changeTokenBalance(remoratoken, owner, -10);
    });
  });
});
