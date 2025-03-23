const {
  loadFixture,
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const {
  deployContractsAndSetVariables,
} = require("../../helpers/setup-contracts");
const { expect } = require("chai");

//Tests are WIP
describe("RemoraRWAToken Rent Forwarding", function () {
  async function holderManagementTestsSetUp() {
    return await deployContractsAndSetVariables(10, 0, 100000, 0, true); //10 cent fee
  }

  describe("Holder Management Tests, rent forwarding", function () {
    it("Should forward payouts from init to different account", async function () {
      const {
        owner,
        investor1,
        investor2,
        remoratoken,
        custodian,
        facilitator,
        allowlist,
        ausd,
      } = await loadFixture(holderManagementTestsSetUp);
      //send stablecoin to payout contract ($1000)
      await ausd.transfer(remoratoken.target, 1000000000);

      await allowlist.connect(custodian).allowUser(owner);
      await allowlist.connect(custodian).allowUser(investor1);
      await allowlist.connect(custodian).allowUser(investor2);

      /*
       * Balances:
       * total: 10
       * owner: 4
       * investor1: 5
       * investor2: 1
       */
      await remoratoken.transfer(investor1.address, 5);
      await remoratoken.transfer(investor2.address, 1);

      //forward rent distribution from investor1 to investor2
      await remoratoken
        .connect(custodian)
        .setPayoutForwardAddress(investor1.address, investor2.address);

      // Call distributePayout ($1000)
      await remoratoken.connect(facilitator).distributePayout(1000000000);

      expect(
        (
          await remoratoken.payoutBalance.staticCallResult(investor1.address)
        ).at(0)
      ).to.equal(0);

      expect(
        (
          await remoratoken.payoutBalance.staticCallResult(investor2.address)
        ).at(0)
      ).to.equal(600000000);

      await expect(
        await remoratoken.connect(investor2).claimPayout()
      ).to.changeTokenBalances(
        ausd,
        [remoratoken, investor2],
        [-599900000, +599900000]
      );
    });

    it("Should forward payouts from init to different account, then remove forwarding and claim payout", async function () {
      const {
        owner,
        investor1,
        investor2,
        remoratoken,
        custodian,
        facilitator,
        allowlist,
        ausd,
      } = await loadFixture(holderManagementTestsSetUp);
      //send stablecoin to payout contract ($10000)
      await ausd.transfer(remoratoken.target, 10000000000);

      await allowlist.connect(custodian).allowUser(owner);
      await allowlist.connect(custodian).allowUser(investor1);
      await allowlist.connect(custodian).allowUser(investor2);

      /*
       * Balances:
       * total: 10
       * owner: 4
       * investor1: 5
       * investor2: 1
       */
      await remoratoken.transfer(investor1.address, 5);
      await remoratoken.transfer(investor2.address, 1);

      //forward payout distribution from investor1 to investor2
      await remoratoken
        .connect(custodian)
        .setPayoutForwardAddress(investor1.address, investor2.address);

      // Call distributePayout ($1000)
      await remoratoken.connect(facilitator).distributePayout(1000000000);

      expect(
        (
          await remoratoken.payoutBalance.staticCallResult(investor1.address)
        ).at(0)
      ).to.equal(0);

      expect(
        (
          await remoratoken.payoutBalance.staticCallResult(investor2.address)
        ).at(0)
      ).to.equal(600000000);

      //Remove payout forwarding
      await remoratoken
        .connect(custodian)
        .removePayoutForwardAddress(investor1.address);

      // Call distributePayout ($1000)
      await remoratoken.connect(facilitator).distributePayout(1000000000);

      expect(
        (
          await remoratoken.payoutBalance.staticCallResult(investor1.address)
        ).at(0)
      ).to.equal(500000000);

      expect(
        (
          await remoratoken.payoutBalance.staticCallResult(investor2.address)
        ).at(0)
      ).to.equal(700000000);

      await expect(
        await remoratoken.connect(investor2).claimPayout()
      ).to.changeTokenBalances(
        ausd,
        [remoratoken, investor2],
        [-699900000, +699900000]
      );
    });

    it("Should distribute payouts correctly, then start forwarding after a payout", async function () {
      const {
        owner,
        investor1,
        investor2,
        remoratoken,
        custodian,
        facilitator,
        allowlist,
        ausd,
      } = await loadFixture(holderManagementTestsSetUp);
      //send stablecoin to payout contract ($1000)
      await ausd.transfer(remoratoken.target, 1000000000);

      await allowlist.connect(custodian).allowUser(owner);
      await allowlist.connect(custodian).allowUser(investor1);
      await allowlist.connect(custodian).allowUser(investor2);

      /*
       * Balances:
       * total: 10
       * owner: 4
       * investor1: 5
       * investor2: 1
       */
      await remoratoken.transfer(investor1.address, 5);
      await remoratoken.transfer(investor2.address, 1);

      // Call distributePayout ($500)
      await remoratoken.connect(facilitator).distributePayout(500000000);

      //forward rent distribution from investor1 to investor2
      await remoratoken
        .connect(custodian)
        .setPayoutForwardAddress(investor1.address, investor2.address);
      await remoratoken.connect(facilitator).distributePayout(500000000);

      expect(
        (
          await remoratoken.payoutBalance.staticCallResult(investor1.address)
        ).at(0)
      ).to.equal(250000000);

      expect(
        (
          await remoratoken.payoutBalance.staticCallResult(investor2.address)
        ).at(0)
      ).to.equal(350000000);

      await expect(
        await remoratoken.connect(investor2).claimPayout()
      ).to.changeTokenBalances(
        ausd,
        [remoratoken, investor2],
        [-349900000, +349900000]
      );
    });
  });
});
