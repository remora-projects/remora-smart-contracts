const {
  loadFixture,
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const {
  deployContractsAndSetVariables,
} = require("../helpers/setup-contracts");
const { allowUsers } = require("../helpers/access-manager-setup");
const {
  checkPayouts,
  payAndCalculate,
} = require("../helpers/holder-management-helper");
const { expect } = require("chai");

describe("RemoraRWAToken Holder Management Tests 1", function () {
  async function holderManagementTestsSetUp() {
    return await deployContractsAndSetVariables(10, 0, 0);
  }

  describe("Holder Management Tests, distributions", function () {
    it("Should revert transfer due to frozen user, then allow after unfrozen", async function () {
      const { owner, investor1, custodian, remoratoken, allowlist } =
        await loadFixture(holderManagementTestsSetUp);

      await allowlist.connect(custodian).allowUser(investor1.address);
      await remoratoken.transfer(investor1.address, 10);

      await remoratoken.connect(custodian).freezeHolder(investor1.address);

      await expect(
        remoratoken.connect(investor1).transfer(owner.address, 10)
      ).to.be.revertedWithCustomError(remoratoken, "UserIsFrozen");

      await remoratoken.connect(custodian).unFreezeHolder(investor1.address);

      await expect(
        remoratoken.connect(investor1).transfer(owner.address, 10)
      ).to.changeTokenBalances(remoratoken, [investor1, owner], [-10, +10]);
    });

    it("Should return 0 for user payout before distributing", async function () {
      const { investor1, custodian, remoratoken, allowlist } =
        await loadFixture(holderManagementTestsSetUp);

      await allowlist.connect(custodian).allowUser(investor1.address);
      await remoratoken.transfer(investor1.address, 1);
      expect(
        (
          await remoratoken.payoutBalance.staticCallResult(investor1.address)
        ).at(0)
      ).to.equal(0);
    });

    it("Should revert claim of 0 when user buys and sells before any payout, at init", async function () {
      const {
        owner,
        investor1,
        custodian,
        facilitator,
        remoratoken,
        allowlist,
      } = await loadFixture(holderManagementTestsSetUp);

      const investors = [owner, investor1];
      const amounts = [BigInt(0), BigInt(0)];
      const totalSupply = await remoratoken.totalSupply();

      await allowUsers(custodian, allowlist, investors);

      //investor 1 has 2 tokens
      await remoratoken.transfer(investor1.address, 2);

      expect(
        (
          await remoratoken.payoutBalance.staticCallResult(investor1.address)
        ).at(0)
      ).to.equal(0);
      await remoratoken.payoutBalance(investor1.address); //non-static call

      //investor 1 has no more tokens
      await remoratoken.connect(investor1).transfer(owner.address, 2);

      await payAndCalculate(
        remoratoken,
        facilitator,
        investors,
        amounts,
        1000000000,
        totalSupply
      );
    });

    it("Should revert claim of 0 when user buys and sells before any payout", async function () {
      const {
        owner,
        investor1,
        custodian,
        facilitator,
        remoratoken,
        allowlist,
      } = await loadFixture(holderManagementTestsSetUp);

      const investors = [owner, investor1];
      const amounts = [BigInt(0), BigInt(0)];
      const totalSupply = await remoratoken.totalSupply();

      await allowUsers(custodian, allowlist, investors);

      //first payout
      await payAndCalculate(
        remoratoken,
        facilitator,
        investors,
        amounts,
        1000000000,
        totalSupply
      );

      //investor 1 has 2 tokens, enters at index 1
      await remoratoken.transfer(investor1.address, 2);

      expect(
        //should have no payout
        (
          await remoratoken.payoutBalance.staticCallResult(investor1.address)
        ).at(0)
      ).to.equal(0);
      await remoratoken.payoutBalance(investor1.address); //non-static call

      //investor 1 has no more tokens
      await remoratoken.connect(investor1).transfer(owner.address, 2);

      await payAndCalculate(
        remoratoken,
        facilitator,
        investors,
        amounts,
        1000000000,
        totalSupply
      );
    });

    it("Should allow user to claim rent after selling all tokens, but not payouts after", async function () {
      const {
        owner,
        investor1,
        custodian,
        facilitator,
        remoratoken,
        allowlist,
        ausd,
      } = await loadFixture(holderManagementTestsSetUp);

      const investors = [owner, investor1];
      const amounts = [BigInt(0), BigInt(0)];
      const totalSupply = await remoratoken.totalSupply();

      await allowUsers(custodian, allowlist, investors);

      //send $10,000 to the contract
      await ausd.transfer(remoratoken.target, 10000000000);

      //investor 1 has 2 tokens enters at init, 0
      await remoratoken.transfer(investor1.address, 2);

      //first payout
      await payAndCalculate(
        remoratoken,
        facilitator,
        investors,
        amounts,
        1000000000,
        totalSupply
      );

      //investor 1 has 4 tokens
      await remoratoken.transfer(investor1.address, 2);

      await payAndCalculate(
        remoratoken,
        facilitator,
        investors,
        amounts,
        1000000000,
        totalSupply
      );

      //investor 1 has no more tokens
      await remoratoken.connect(investor1).transfer(owner.address, 4);

      await payAndCalculate(
        remoratoken,
        facilitator,
        investors,
        amounts,
        1000000000,
        totalSupply
      );
      await payAndCalculate(
        remoratoken,
        facilitator,
        investors,
        amounts,
        1000000000,
        totalSupply
      );

      expect(
        await remoratoken.connect(investor1).claimPayout()
      ).to.changeTokenBalances(
        ausd,
        [remoratoken, investor1],
        [-Number(amounts[1]), +Number(amounts[1])]
      );

      await payAndCalculate(
        remoratoken,
        facilitator,
        investors,
        amounts,
        1000000000,
        totalSupply
      );

      await expect(
        remoratoken.connect(investor1).claimPayout()
      ).to.be.revertedWithCustomError(remoratoken, "NoPayoutToClaim");
    });

    it("Should allow claim of older payouts but not new payouts, after User sold all tokens", async function () {
      const {
        owner,
        investor1,
        custodian,
        facilitator,
        remoratoken,
        allowlist,
        ausd,
      } = await loadFixture(holderManagementTestsSetUp);

      await allowlist.connect(custodian).allowUser(investor1.address);

      //send $10,000 to the contract
      await ausd.transfer(remoratoken.target, 10000000000);

      //investor 1 has 2 tokens enters at init, 0
      await remoratoken.transfer(investor1.address, 2);

      //first payout
      await remoratoken.connect(facilitator).distributePayout(1000000000);
      await remoratoken.connect(facilitator).distributePayout(1000000000);

      //investor has no more tokens
      await remoratoken.connect(investor1).transfer(owner.address, 2);

      await remoratoken.connect(facilitator).distributePayout(1000000000);
      await remoratoken.connect(facilitator).distributePayout(1000000000);
      await remoratoken.connect(facilitator).distributePayout(1000000000);

      expect(
        await remoratoken.connect(investor1).claimPayout()
      ).to.changeTokenBalances(
        ausd,
        [remoratoken, investor1],
        [-400000000, +400000000]
      );
    });

    it("Should calculate correct payout even if buyer never checks after multiple distributions", async function () {
      const {
        investor1,
        custodian,
        facilitator,
        remoratoken,
        allowlist,
        ausd,
      } = await loadFixture(holderManagementTestsSetUp);

      await allowlist.connect(custodian).allowUser(investor1.address);

      //send $10,000 to the contract
      await ausd.transfer(remoratoken.target, 10000000000);

      //investor 1 has 2 tokens enters at init, 0
      await remoratoken.transfer(investor1.address, 4);

      //first payout
      await remoratoken.connect(facilitator).distributePayout(1000000000);
      await remoratoken.connect(facilitator).distributePayout(1000000000);
      await remoratoken.connect(facilitator).distributePayout(1000000000);
      await remoratoken.connect(facilitator).distributePayout(1000000000);

      expect(
        await remoratoken.connect(investor1).claimPayout()
      ).to.changeTokenBalances(
        ausd,
        [remoratoken, investor1],
        [-2000000000, +2000000000]
      );
    });

    it("Should distribute correct amount with multiple distributions, transfers in between, and investors at different points", async function () {
      const {
        owner,
        investor1,
        investor2,
        investor3,
        investor4,
        facilitator,
        custodian,
        allowlist,
        remoratoken,
      } = await loadFixture(holderManagementTestsSetUp);

      const totalSupply = BigInt(await remoratoken.totalSupply());
      const investors = [owner, investor1, investor2, investor3, investor4];
      const amounts = [BigInt(0), BigInt(0), BigInt(0), BigInt(0), BigInt(0)];

      await allowUsers(custodian, allowlist, investors);

      // transfer 1 token to investor
      await remoratoken.transfer(investor1.address, 1); // user is now added as a new user.
      await remoratoken.transfer(investor2.address, 1);

      // Call distributePayout ($1000)
      await payAndCalculate(
        remoratoken,
        facilitator,
        investors,
        amounts,
        BigInt(1000000000),
        totalSupply
      );

      await remoratoken.transfer(investor2.address, 1);
      await checkPayouts(remoratoken, investors, amounts);

      // Call distributePayout ($1000)
      await payAndCalculate(
        remoratoken,
        facilitator,
        investors,
        amounts,
        BigInt(1000000000),
        totalSupply
      );

      await remoratoken.transfer(investor3.address, 1);
      await checkPayouts(remoratoken, investors, amounts);

      // Call distributePayout ($1000)
      await payAndCalculate(
        remoratoken,
        facilitator,
        investors,
        amounts,
        BigInt(1000000000),
        totalSupply
      );

      await remoratoken.transfer(investor2.address, 4);

      await checkPayouts(remoratoken, investors, amounts);

      await remoratoken.connect(investor2).transfer(investor3, 1);

      // Call distributePayout ($1000)
      await payAndCalculate(
        remoratoken,
        facilitator,
        investors,
        amounts,
        BigInt(1000000000),
        totalSupply
      );

      await remoratoken.transfer(investor4.address, 1);

      await checkPayouts(remoratoken, investors, amounts);
    });

    it("Should distribute correct amount with multiple distributions, transfers in between, and investors at different points (with claims)", async function () {
      const {
        owner,
        investor1,
        investor2,
        investor3,
        investor4,
        facilitator,
        custodian,
        remoratoken,
        allowlist,
        ausd,
      } = await loadFixture(holderManagementTestsSetUp);

      const totalSupply = BigInt(await remoratoken.totalSupply());
      const investors = [owner, investor1, investor2, investor3, investor4];
      const amounts = [BigInt(0), BigInt(0), BigInt(0), BigInt(0), BigInt(0)];

      await allowUsers(custodian, allowlist, investors);

      //send $10,000 to the contract
      await ausd.transfer(remoratoken.target, 10000000000);

      // transfer 1 token to investor
      await remoratoken.transfer(investor1.address, 1); // user is now added as a new user.
      await remoratoken.transfer(investor2.address, 1);

      // Call distributePayout ($1000)
      await payAndCalculate(
        remoratoken,
        facilitator,
        investors,
        amounts,
        BigInt(1000000000),
        totalSupply
      );

      await remoratoken.transfer(investor2.address, 1);

      await checkPayouts(remoratoken, investors, amounts);

      // Call distributePayout ($1000)
      await payAndCalculate(
        remoratoken,
        facilitator,
        investors,
        amounts,
        BigInt(1000000000),
        totalSupply
      );

      await remoratoken.transfer(investor3.address, 1);

      await checkPayouts(remoratoken, investors, amounts);

      await remoratoken.connect(investor1).claimPayout(); // 0 for investor 1
      amounts[1] = BigInt(0);

      // Call distributePayout ($1000)
      await payAndCalculate(
        remoratoken,
        facilitator,
        investors,
        amounts,
        BigInt(1000000000),
        totalSupply
      );

      await remoratoken.transfer(investor2.address, 4); // 6 total

      await checkPayouts(remoratoken, investors, amounts);

      await remoratoken.connect(investor2).transfer(investor3, 1);

      await remoratoken.connect(investor2).claimPayout(); // 0 for investor 2
      amounts[2] = BigInt(0);

      // Call distributePayout ($1000)
      await payAndCalculate(
        remoratoken,
        facilitator,
        investors,
        amounts,
        BigInt(1000000000),
        totalSupply
      );

      await remoratoken.transfer(investor4.address, 1);
      await checkPayouts(remoratoken, investors, amounts);
    });
  });
});
