const {
  loadFixture,
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { setUpAndDeployContracts } = require("./helpers/SetUpContracts");
const { ethers, upgrades } = require("hardhat");
const { expect } = require("chai");

describe("RemoraRWAToken", function () {
  async function deployContractsAndSetVariables() {
    const [owner, investor1, investor2, custodian, facilitator, state_changer] =
      await ethers.getSigners();

    const { remoratoken, allowlist, ausd, accessmanager } =
      await setUpAndDeployContracts(
        owner,
        custodian,
        facilitator,
        state_changer
      );

    return {
      owner,
      investor1,
      investor2,
      custodian,
      facilitator,
      state_changer,
      remoratoken,
      allowlist,
      ausd,
      accessmanager,
    };
  }

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

    it("Should revert due to transfer to unregistered user", async function () {
      const { owner, investor1, facilitator, remoratoken, allowlist } =
        await loadFixture(deployContractsAndSetVariables);

      await remoratoken.approve(facilitator.address, 10);

      await expect(
        remoratoken
          .connect(facilitator)
          .transferFrom(owner.address, investor1.address, 10)
      ).to.be.revertedWithCustomError(allowlist, "UserNotRegistered");
    });

    it("Should revert due to restricted transfer", async function () {
      const { investor1, custodian, remoratoken, allowlist } =
        await loadFixture(deployContractsAndSetVariables);

      await allowlist.connect(custodian).allowUser(investor1.address);
      await expect(
        remoratoken.transfer(investor1.address, 10)
      ).to.be.revertedWithCustomError(remoratoken, "AccessManagedUnauthorized");
    });
  });
  describe("Burnable Tests", function () {});
  describe("Holder Management Tests", function () {
    it("Should revert transfer due to frozen user", async function () {
      const {
        owner,
        investor1,
        custodian,
        facilitator,
        remoratoken,
        allowlist,
      } = await loadFixture(deployContractsAndSetVariables);

      await allowlist.connect(custodian).allowUser(investor1.address);
      await remoratoken.approve(facilitator.address, 10);
      await remoratoken
        .connect(facilitator)
        .transferFrom(owner.address, investor1.address, 10);

      await remoratoken.connect(investor1).approve(owner.address, 10);
      await remoratoken.connect(custodian).freezeHolder(investor1.address);

      await expect(
        remoratoken
          .connect(facilitator)
          .transferFrom(investor1.address, owner.address, 10)
      ).to.be.revertedWithCustomError(remoratoken, "UserIsFrozen");
    });
  });
});
