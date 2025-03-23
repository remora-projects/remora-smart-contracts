const {
  loadFixture,
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const {
  deployContractsAndSetVariables,
} = require("../helpers/setup-contracts");
const { time } = require("@nomicfoundation/hardhat-network-helpers");
const { expect } = require("chai");

describe("RemoraRWAToken Lock Up Tests", function () {
  async function setUpRemoraRWALockUpTests() {
    return await deployContractsAndSetVariables(10, 0, 0, 86400, true); //1 day lock up
  }

  it("Should allow transfer of token after 1 day lock up", async function () {
    const { owner, investor1, custodian, remoratoken, allowlist } =
      await loadFixture(setUpRemoraRWALockUpTests);

    await allowlist.connect(custodian).allowUser(investor1.address);
    await remoratoken.transfer(investor1.address, 10);

    await expect(
      remoratoken.connect(investor1).transfer(owner.address, 10)
    ).to.be.revertedWithCustomError(
      remoratoken,
      "InsufficientTokensUnlockable"
    );

    await time.increase(86400); //1 day pass

    await expect(
      remoratoken.connect(investor1).transfer(owner.address, 10)
    ).to.changeTokenBalances(remoratoken, [investor1, owner], [-10, +10]);
  });

  it("Should allow transfer of many tokens purchased at different times", async function () {
    const { owner, investor1, custodian, remoratoken, allowlist } =
      await loadFixture(setUpRemoraRWALockUpTests);

    await allowlist.connect(custodian).allowUser(investor1.address);
    await remoratoken.transfer(investor1.address, 1);

    await time.increase(86400); //1 day pass

    await remoratoken.transfer(investor1.address, 1);

    //should be able to sell 1 token only
    await expect(
      remoratoken.connect(investor1).transfer(owner.address, 2)
    ).to.be.revertedWithCustomError(
      remoratoken,
      "InsufficientTokensUnlockable"
    );

    await expect(
      remoratoken.connect(investor1).transfer(owner.address, 1)
    ).to.changeTokenBalances(remoratoken, [investor1, owner], [-1, +1]);

    await remoratoken.transfer(investor1.address, 1);

    await time.increase(172800); //2 days pass

    await expect(
      remoratoken.connect(investor1).transfer(owner.address, 2)
    ).to.changeTokenBalances(remoratoken, [investor1, owner], [-2, +2]);
  });
});
