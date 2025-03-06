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
const { time } = require("@nomicfoundation/hardhat-network-helpers");

describe("RemoraRWAToken", function () {
  async function freezingFixture() {
    return await deployContractsAndSetVariables(10, 0, 0, true);
  }

  describe("Freezing Tests", function () {
    it("Should revert transfer due to frozen user, then allow after unfrozen", async function () {
      const { owner, investor1, custodian, remoratoken, allowlist } =
        await loadFixture(freezingFixture);

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

    it("Should freeze holder from init but allow claim of all funds after unfrozen (with fee)", async function () {
      const { owner, investor1, remoratoken, accessmanager, allowlist, ausd } =
        await loadFixture(freezingFixture);

      await accessmanager.grantRole(FACILITATOR_ID, owner, 0);
      await accessmanager.grantRole(CUSTODIAN_ID, owner, 0);
      await allowlist.allowUser(investor1);
      await remoratoken.setPayoutFee(10000);

      //send stablecoin to payout contract ($1000)
      await ausd.transfer(remoratoken.target, 10000000000);

      // transfer 1 token to investor
      await remoratoken.transfer(investor1.address, 1);
      await remoratoken.freezeHolder(investor1.address);

      expect(await remoratoken.isHolderFrozen(investor1.address)).to.equal(
        true
      );

      // Call distributePayout ($1000)
      await remoratoken.distributePayout(1000000000);
      await remoratoken.distributePayout(1000000000);
      await remoratoken.distributePayout(1000000000);
      await remoratoken.distributePayout(1000000000);

      //rent payout balance
      expect(
        (
          await remoratoken.payoutBalance.staticCallResult(investor1.address)
        ).at(0)
      ).to.equal(0); //$0
      await remoratoken.payoutBalance(investor1.address);

      await remoratoken.unFreezeHolder(investor1.address);

      expect(
        (
          await remoratoken.payoutBalance.staticCallResult(investor1.address)
        ).at(0)
      ).to.equal(400000000); //$400
      await remoratoken.payoutBalance(owner.address);

      expect(
        await remoratoken.connect(investor1).claimPayout()
      ).to.changeTokenBalances(
        ausd,
        [remoratoken, investor1],
        [-360000000, +360000000]
      ); // $360 claimed with fee

      expect(
        (
          await remoratoken.payoutBalance.staticCallResult(investor1.address)
        ).at(0)
      ).to.equal(0); //$0
    });

    it("Should only allow unfrozen balance claim when user is frozen, but allow claim of all funds after unfrozen", async function () {
      const { owner, investor1, remoratoken, accessmanager, allowlist, ausd } =
        await loadFixture(freezingFixture);

      const investors = [owner, investor1];
      const amounts = [BigInt(0), BigInt(0)];
      const totalSupply = await remoratoken.totalSupply();

      await accessmanager.grantRole(FACILITATOR_ID, owner, 0);
      await accessmanager.grantRole(CUSTODIAN_ID, owner, 0);
      await allowlist.allowUser(investor1);
      await remoratoken.setPayoutFee(10000);

      //send stablecoin to payout contract ($1000)
      await ausd.transfer(remoratoken.target, 10000000000);

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

      //freeze user
      await remoratoken.freezeHolder(investor1.address);
      expect(await remoratoken.isHolderFrozen(investor1.address)).to.equal(
        true
      );

      // Call distributePayout ($1000)
      await payAndCalculate(
        remoratoken,
        owner,
        investors,
        amounts,
        1000000000,
        totalSupply
      );

      //rent payout balance
      await checkPayouts(remoratoken, investors, amounts);

      expect(
        await remoratoken.connect(investor1).claimPayout()
      ).to.changeTokenBalances(
        ausd,
        [remoratoken, investor1],
        [-90000000, +90000000]
      ); // $90 claimed with fee
      amounts[1] = BigInt(0);

      await checkPayouts(remoratoken, investors, amounts);

      await remoratoken.unFreezeHolder(investor1.address);

      //frozen funds should be unfrozen and claimable
      await checkPayouts(remoratoken, investors, amounts);

      expect(
        await remoratoken.connect(investor1).claimPayout()
      ).to.changeTokenBalances(
        ausd,
        [remoratoken, investor1],
        [-90000000, +90000000]
      ); // $90 claimed with fee
    });

    it("Should revoke frozen user's token after 30 days + revoke TC signature", async function () {
      const {
        owner,
        investor1,
        custodian,
        facilitator,
        remoratoken,
        allowlist,
      } = await loadFixture(freezingFixture);

      await allowlist.connect(custodian).allowUser(investor1.address);
      await remoratoken.transfer(investor1.address, 2);

      await remoratoken.connect(custodian).freezeHolder(investor1.address);

      await expect(
        remoratoken
          .connect(facilitator)
          .adminTransferFrom(investor1.address, owner.address, 2, false)
      ).to.be.revertedWithCustomError(
        remoratoken,
        "ERC20InsufficientAllowance"
      );

      await time.increase(2592000); //30 days pass

      await expect(
        remoratoken
          .connect(facilitator)
          .adminTransferFrom(investor1.address, owner.address, 2, false)
      ).to.changeTokenBalances(remoratoken, [investor1, owner], [-2, +2]);

      expect(await remoratoken.hasSignedTC(investor1.address)).to.be.false;
    });
  });
});
