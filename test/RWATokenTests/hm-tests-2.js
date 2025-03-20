const {
  loadFixture,
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const {
  deployContractsAndSetVariables,
} = require("../helpers/setup-contracts");
const {
  CUSTODIAN_ID,
  FACILITATOR_ID,
} = require("../helpers/access-manager-setup");
const {
  payAndCalculate,
  checkPayouts,
} = require("../helpers/holder-management-helper");
const { expect } = require("chai");

describe("RemoraRWAToken Holder Management Tests 2", function () {
  async function holderManagementTestsSetUp() {
    return await deployContractsAndSetVariables(10, 0, 10000, 0, true); //10% fee
  }

  describe("Holder Management Tests, claims + fee", function () {
    it("Should distribute payouts correctly with Fee, plus withdraw to wallet", async function () {
      const { owner, investor1, remoratoken, accessmanager, allowlist, ausd } =
        await loadFixture(holderManagementTestsSetUp);

      const investors = [owner, investor1];
      const amounts = [BigInt(0), BigInt(0)];
      const totalSupply = await remoratoken.totalSupply();

      await accessmanager.grantRole(FACILITATOR_ID, owner, 0);
      await accessmanager.grantRole(CUSTODIAN_ID, owner, 0);
      await allowlist.allowUser(investor1);

      //send stablecoin to payout contract ($1000)
      await ausd.transfer(remoratoken.target, 1000000000);

      await remoratoken.transfer(investor1.address, 1);

      // Call distributePayout ($1000)
      await payAndCalculate(
        remoratoken,
        owner,
        investors,
        amounts,
        1000000000,
        totalSupply
      );
      await checkPayouts(remoratoken, investors, amounts);

      //investor claims payout with fee
      expect(
        await remoratoken.connect(investor1).claimPayout()
      ).to.changeTokenBalances(
        ausd,
        [remoratoken, investor1],
        [-90000000, +90000000]
      ); // +- $90
      expect(
        (
          await remoratoken.payoutBalance.staticCallResult(investor1.address)
        ).at(0)
      ).to.equal(0);

      //owner claims rent, no fee
      await remoratoken.claimPayout();
      expect(
        (await remoratoken.payoutBalance.staticCallResult(owner.address)).at(0)
      ).to.equal(0);
      await remoratoken.payoutBalance(owner.address);

      //withdraw stablecoin from contract
      expect(await remoratoken.withdraw(true, 0)).to.changeTokenBalances(
        ausd,
        [remoratoken, owner],
        [-910000000, +910000000]
      );
    });

    it("Should distribute payouts correctly with fee, then with fee change", async function () {
      const { owner, investor1, remoratoken, allowlist, accessmanager, ausd } =
        await loadFixture(holderManagementTestsSetUp);

      const investors = [owner, investor1];
      const amounts = [BigInt(0), BigInt(0)];
      const totalSupply = await remoratoken.totalSupply();

      await accessmanager.grantRole(FACILITATOR_ID, owner, 0);
      await accessmanager.grantRole(CUSTODIAN_ID, owner, 0);
      await allowlist.allowUser(investor1);

      //send stablecoin to payout contract ($2000)
      await ausd.transfer(remoratoken.target, 2000000000);

      await remoratoken.transfer(investor1.address, 1);

      // Call distributePayout ($1000)
      await payAndCalculate(
        remoratoken,
        owner,
        investors,
        amounts,
        1000000000,
        totalSupply
      );

      await checkPayouts(remoratoken, investors, amounts);

      //investor claims rent with fee
      expect(
        await remoratoken.connect(investor1).claimPayout()
      ).to.changeTokenBalances(
        ausd,
        [remoratoken, investor1],
        [-90000000, +90000000]
      ); // +- $90

      await remoratoken.setPayoutFee(20000); //20% fee

      // Call distributePayout ($1000)
      await payAndCalculate(
        remoratoken,
        owner,
        investors,
        amounts,
        1000000000,
        totalSupply
      );

      await checkPayouts(remoratoken, investors, amounts);

      //investor claims rent with new fee
      expect(
        await remoratoken.connect(investor1).claimPayout()
      ).to.changeTokenBalances(
        ausd,
        [remoratoken, investor1],
        [-80000000, +80000000]
      ); // +- $80

      //owner claims rent, no fee
      await remoratoken.claimPayout();
      expect(
        (await remoratoken.payoutBalance.staticCallResult(owner.address)).at(0)
      ).to.equal(0);
      await remoratoken.payoutBalance(owner.address);

      //withdraw stablecoin from contract
      expect(await remoratoken.withdraw(true, 0)).to.changeTokenBalances(
        ausd,
        [remoratoken, owner],
        [-1830000000, +1830000000]
      );
    });

    it("Should revert with Insufficient stablecoin balance when investor claims payout because contract has no balance", async function () {
      const { owner, investor1, remoratoken, accessmanager, allowlist, ausd } =
        await loadFixture(holderManagementTestsSetUp);

      const investors = [owner, investor1];
      const amounts = [BigInt(0), BigInt(0)];
      const totalSupply = await remoratoken.totalSupply();

      await accessmanager.grantRole(FACILITATOR_ID, owner, 0);
      await accessmanager.grantRole(CUSTODIAN_ID, owner, 0);
      await allowlist.allowUser(investor1);

      //send stablecoin to payout contract ($100)
      await ausd.transfer(remoratoken.target, 100000000);

      // transfer 1 token to investor
      await remoratoken.transfer(investor1.address, 1);

      // Call distributePayout ($1000)
      await payAndCalculate(
        remoratoken,
        owner,
        investors,
        amounts,
        1000000000,
        totalSupply
      );

      await checkPayouts(remoratoken, investors, amounts);

      //investor claims rent with fee
      expect(
        await remoratoken.connect(investor1).claimPayout()
      ).to.be.revertedWithCustomError(
        remoratoken,
        "InsufficentStablecoinBalance"
      );
    });

    it("Should revert payout distribution and claim by unauthorized accounts, plus empty claim by authorized user", async function () {
      const {
        custodian,
        investor1,
        investor2,
        facilitator,
        allowlist,
        remoratoken,
      } = await loadFixture(holderManagementTestsSetUp);

      await expect(
        remoratoken.connect(investor2).distributePayout(1000)
      ).to.be.revertedWithCustomError(remoratoken, "AccessManagedUnauthorized");

      await remoratoken.connect(facilitator).distributePayout(1000);
      await allowlist.connect(custodian).allowUser(investor1.address);

      await expect(
        remoratoken.connect(investor2).claimPayout()
      ).to.be.revertedWithCustomError(remoratoken, "NoPayoutToClaim");

      await expect(
        remoratoken.connect(investor1).claimPayout()
      ).to.be.revertedWithCustomError(remoratoken, "NoPayoutToClaim");
    });
  });
});
