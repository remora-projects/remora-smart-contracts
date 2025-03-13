const {
  loadFixture,
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const {
  deployContractsAndSetVariables,
} = require("../helpers/setup-contracts");
const { expect } = require("chai");

describe("RemoraRWAToken", function () {
  async function burnableFixture() {
    return await deployContractsAndSetVariables(10, 0, 0, 0, true);
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

      await remoratoken.connect(state_changer).enableBurning(false, 0);

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

      await remoratoken.connect(state_changer).enableBurning(false, 0);

      await expect(
        remoratoken.connect(state_changer).burnFrom(owner.address, 10)
      ).to.be.revertedWithCustomError(remoratoken, "AccessManagedUnauthorized");

      await expect(
        remoratoken.connect(facilitator).burnFrom(owner.address, 10)
      ).to.changeTokenBalance(remoratoken, owner, -10);
    });

    it("Should successfully payout investor after burning token", async function () {
      const {
        investor1,
        custodian,
        state_changer,
        remoratoken,
        ausd,
        allowlist,
      } = await loadFixture(burnableFixture);

      await allowlist.connect(custodian).allowUser(investor1.address);

      await ausd.transfer(remoratoken.target, 1250000);
      await remoratoken.connect(state_changer).enableBurning(true, 250000); // payout 25 cents per token

      await remoratoken.transfer(investor1.address, 5);

      const tx = remoratoken.connect(investor1).burn(5);
      await expect(tx).to.changeTokenBalance(remoratoken, investor1, -5);

      await expect(tx).to.changeTokenBalances(
        ausd,
        [investor1, remoratoken],
        [+1250000, -1250000]
      );
    });
  });
});
