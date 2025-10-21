import { Cl } from "@stacks/transactions";
import { describe, expect, it } from "vitest";

const accounts = simnet.getAccounts();
const deployer = accounts.get("deployer")!;
const wallet1 = accounts.get("wallet_1")!;
const wallet2 = accounts.get("wallet_2")!;
const wallet3 = accounts.get("wallet_3")!;

describe("Patient Incentive System Tests", () => {
  it("ensures simnet is initialized", () => {
    expect(simnet.blockHeight).toBeDefined();
  });

  it("initializes with default clinic", () => {
    const { result } = simnet.callReadOnlyFn(
      "patient-incentive-system",
      "get-clinic-info",
      [Cl.uint(1)],
      deployer
    );
    
    expect(result).toBeSome(
      Cl.tuple({
        name: Cl.stringAscii("Community Health Center"),
        "reward-rate": Cl.uint(50),
        "is-verified": Cl.bool(true),
        "total-patients": Cl.uint(0)
      })
    );
  });

  it("allows contract owner to register new clinic", () => {
    const { result } = simnet.callPublicFn(
      "patient-incentive-system",
      "register-clinic",
      [Cl.stringAscii("Downtown Medical Center"), Cl.uint(75)],
      deployer
    );
    
    expect(result).toBeOk(Cl.uint(2)); // Next clinic ID should be 2
    
    // Verify clinic was registered
    const clinicInfo = simnet.callReadOnlyFn(
      "patient-incentive-system",
      "get-clinic-info",
      [Cl.uint(2)], // Check the clinic that was actually created
      deployer
    );
    
    expect(clinicInfo.result).toBeSome(
      Cl.tuple({
        name: Cl.stringAscii("Downtown Medical Center"),
        "reward-rate": Cl.uint(75),
        "is-verified": Cl.bool(true),
        "total-patients": Cl.uint(0)
      })
    );
  });

  it("allows patient registration with valid clinic", () => {
    const { result } = simnet.callPublicFn(
      "patient-incentive-system",
      "register-patient",
      [Cl.uint(1)],
      wallet1
    );
    
    expect(result).toBeOk(Cl.bool(true));
    
    // Verify patient was registered
    const patientInfo = simnet.callReadOnlyFn(
      "patient-incentive-system",
      "get-patient-info",
      [Cl.principal(wallet1)],
      deployer
    );
    
    expect(patientInfo.result).toBeSome(
      Cl.tuple({
        "total-visits": Cl.uint(0),
        "reward-points": Cl.uint(0),
        "last-visit": Cl.uint(0),
        "clinic-id": Cl.uint(1),
        "is-active": Cl.bool(true)
      })
    );
  });

  it("records patient visits and awards points", () => {
    // First register the patient
    simnet.callPublicFn(
      "patient-incentive-system",
      "register-patient",
      [Cl.uint(1)],
      wallet1
    );
    
    // Record a visit
    const { result } = simnet.callPublicFn(
      "patient-incentive-system",
      "record-visit",
      [Cl.principal(wallet1), Cl.stringAscii("check-up"), Cl.uint(1)],
      deployer
    );
    
    expect(result).toBeOk(
      Cl.tuple({
        "visit-id": Cl.uint(1),
        "reward-earned": Cl.uint(50) // Base reward rate for clinic 1
      })
    );
  });

  it("calculates loyalty bonus correctly", () => {
    // Test loyalty bonus calculation for different visit counts
    const bonus0 = simnet.callReadOnlyFn(
      "patient-incentive-system",
      "calculate-loyalty-bonus",
      [Cl.uint(3)],
      deployer
    );
    expect(bonus0.result).toBeUint(0); // No bonus for < 5 visits
    
    const bonus25 = simnet.callReadOnlyFn(
      "patient-incentive-system",
      "calculate-loyalty-bonus",
      [Cl.uint(7)],
      deployer
    );
    expect(bonus25.result).toBeUint(25); // 25% bonus for 5-9 visits
    
    const bonus50 = simnet.callReadOnlyFn(
      "patient-incentive-system",
      "calculate-loyalty-bonus",
      [Cl.uint(12)],
      deployer
    );
    expect(bonus50.result).toBeUint(50); // 50% bonus for 10+ visits
  });

  it("provides correct patient statistics", () => {
    // First register the patient
    simnet.callPublicFn(
      "patient-incentive-system",
      "register-patient",
      [Cl.uint(1)],
      wallet1
    );
    
    // Record a visit to generate stats
    simnet.callPublicFn(
      "patient-incentive-system",
      "record-visit",
      [Cl.principal(wallet1), Cl.stringAscii("check-up"), Cl.uint(1)],
      deployer
    );
    
    const { result } = simnet.callReadOnlyFn(
      "patient-incentive-system",
      "get-patient-stats",
      [Cl.principal(wallet1)],
      deployer
    );
    
    expect(result).toBeOk(
      Cl.tuple({
        "total-visits": Cl.uint(1),
        "reward-points": Cl.uint(50),
        "loyalty-level": Cl.stringAscii("Bronze"),
        "next-bonus-visits": Cl.uint(4)
      })
    );
  });
});
