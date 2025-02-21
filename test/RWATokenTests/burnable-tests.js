const {
  loadFixture,
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const {
  deployContractsAndSetVariables,
} = require("../helpers/setup-contracts");
const { expect } = require("chai");

describe("RemoraRWAToken", function () {
  async function burnableFixture() {
    return await deployContractsAndSetVariables(10, 0, 0, true);
  }

  describe("Burnable Tests", function () {
    it("Should revert due to burning disabled, then burn tokens successfully after enable", async function () {
      const { owner, state_changer, remoratoken } = await loadFixture(
        burnableFixture
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
        await loadFixture(burnableFixture);

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
