import { Cl } from "@stacks/transactions";
import { describe, expect, it } from "vitest";

const accounts = simnet.getAccounts();
const deployer = accounts.get("deployer")!;
const wallet1 = accounts.get("wallet_1")!;
const wallet2 = accounts.get("wallet_2")!;

describe("Medical Supply Tracker Smart Contract", () => {

  it("ensures simnet is initialized", () => {
    expect(simnet.blockHeight).toBeDefined();
  });

  it("should initialize with sample supplies for clinic 1", () => {
    const { result } = simnet.callReadOnlyFn(
      "medical-supply-tracker",
      "get-supply-info",
      [Cl.uint(1), Cl.uint(1)],
      deployer
    );
    
    expect(result).toBeSome(
      Cl.tuple({
        name: Cl.stringAscii("Surgical Masks"),
        category: Cl.uint(3),
        "current-quantity": Cl.uint(500),
        "minimum-threshold": Cl.uint(100),
        "maximum-capacity": Cl.uint(1000),
        "unit-cost": Cl.uint(2),
        supplier: Cl.stringAscii("MedSupply Corp"),
        "last-restocked": Cl.uint(2),
        "expiry-date": Cl.uint(5002),
        "is-critical": Cl.bool(false)
      })
    );
  });

  it("should show correct system stats", () => {
    const { result } = simnet.callReadOnlyFn(
      "medical-supply-tracker",
      "get-system-stats",
      [],
      deployer
    );
    
    expect(result).toBeOk(
      Cl.tuple({
        "total-supplies-tracked": Cl.uint(2),
        "system-alerts-count": Cl.uint(0),
        "next-supply-id": Cl.uint(3),
        "next-batch-id": Cl.uint(1)
      })
    );
  });

  it("should successfully add a new medical supply", () => {
    const { result } = simnet.callPublicFn(
      "medical-supply-tracker",
      "add-medical-supply",
      [
        Cl.uint(1), // clinic-id
        Cl.stringAscii("Antibiotics"), // name
        Cl.uint(1), // category (MEDICATION)
        Cl.uint(100), // initial-quantity
        Cl.uint(20), // minimum-threshold
        Cl.uint(200), // maximum-capacity
        Cl.uint(10), // unit-cost
        Cl.stringAscii("PharmaCorp"), // supplier
        Cl.uint(10000) // expiry-date
      ],
      deployer
    );

    expect(result).toBeOk(Cl.uint(3)); // New supply ID
  });

  it("should check low stock correctly", () => {
    // First add a supply with low stock
    simnet.callPublicFn(
      "medical-supply-tracker",
      "add-medical-supply",
      [
        Cl.uint(1),
        Cl.stringAscii("Low Stock Item"),
        Cl.uint(2),
        Cl.uint(15), // current quantity
        Cl.uint(20), // minimum threshold (15 <= 20 = low stock)
        Cl.uint(100),
        Cl.uint(5),
        Cl.stringAscii("Supplier"),
        Cl.uint(5000)
      ],
      deployer
    );

    const { result } = simnet.callReadOnlyFn(
      "medical-supply-tracker",
      "check-low-stock",
      [Cl.uint(1), Cl.uint(3)],
      deployer
    );

    expect(result).toBeOk(
      Cl.tuple({
        "is-low-stock": Cl.bool(true),
        "current-quantity": Cl.uint(15),
        "minimum-threshold": Cl.uint(20),
        "reorder-amount": Cl.uint(85) // 100 - 15
      })
    );
  });
});
