// test/payroll_calculator_test.dart
import 'package:flutter_test/flutter_test.dart';
import '../lib/services/payroll_calculator.dart';

const PayrollSettings _defaults = PayrollSettings();

/// Full attendance (22/22 days), no allowances, optional work-hour totals.
PayrollBreakdown _run(
  double basic, {
  WorkHoursTotals hours = const WorkHoursTotals(),
  PayrollSettings settings = _defaults,
}) {
  return PayrollCalculator.computeFromData(
    employee: <String, dynamic>{
      'basicSalary': basic,
      'workingDaysPerMonth': 22,
    },
    expectedDays: 22,
    present: 22,
    workHours: hours,
    settings: settings,
  );
}

Matcher _peso(double v) => closeTo(v, 0.005);

void main() {
  group('Contributions and withholding tax', () {
    test('P18,000: SSS 5% of MSC, Pag-IBIG capped at 200, tax 0', () {
      final b = _run(18000);
      expect(b.earnedBasic, _peso(18000.00));
      expect(b.sss, _peso(900.00)); // MSC 18,000 x 5%
      expect(b.philhealth, _peso(450.00));
      expect(b.pagibig, _peso(200.00)); // 2% would be 360
      expect(b.taxableIncome, _peso(16450.00));
      expect(b.taxWithheld, _peso(0.00));
      expect(b.netPay, _peso(16450.00));
    });

    test('P40,000: MSC capped at 35,000, 20% bracket applies', () {
      final b = _run(40000);
      expect(b.sss, _peso(1750.00)); // 35,000 x 5%
      expect(b.philhealth, _peso(1000.00));
      expect(b.pagibig, _peso(200.00));
      expect(b.taxableIncome, _peso(37050.00));
      expect(b.taxWithheld, _peso(2618.40)); // 1,875 + (37,050-33,333) x 20%
      expect(b.netPay, _peso(34431.60));
    });

    test('Pag-IBIG low-salary rate and cap', () {
      expect(PayrollCalculator.calcPagibig(1000, _defaults), _peso(10.00));
      expect(PayrollCalculator.calcPagibig(50000, _defaults), _peso(200.00));
    });

    test('BIR brackets are continuous at the boundaries', () {
      expect(PayrollCalculator.calcWithholdingTax(20833, _defaults), _peso(0));
      expect(PayrollCalculator.calcWithholdingTax(33333, _defaults), _peso(1875.00));
      expect(PayrollCalculator.calcWithholdingTax(66667, _defaults), _peso(8541.80));
    });

    test('Rates are settings-driven (SSS 4% gives 720 at P18,000)', () {
      final b = _run(18000, settings: const PayrollSettings(sssEmployeeRate: 0.04));
      expect(b.sss, _peso(720.00));
    });
  });

  group('Overtime and night differential (hourly rate 102.2727)', () {
    test('2h ordinary OT at 125% = 255.68', () {
      final b = _run(18000, hours: const WorkHoursTotals(regularOtMinutes: 120));
      expect(b.overtimeHours, closeTo(2.0, 1e-9));
      expect(b.overtimeAmount, _peso(255.68));
    });

    test('2h rest-day OT at 169% = 345.68', () {
      final b = _run(18000, hours: const WorkHoursTotals(restDayOtMinutes: 120));
      expect(b.dayOffOtAmount, _peso(345.68));
    });

    test('4h night differential at 10% = 40.91', () {
      final b = _run(18000, hours: const WorkHoursTotals(nightDiffMinutes: 240));
      expect(b.nightDiffHours, closeTo(4.0, 1e-9));
      expect(b.nightDiffAmount, _peso(40.91));
    });

    test('OT multiplier is settings-driven (150% gives 306.82)', () {
      final b = _run(
        18000,
        hours: const WorkHoursTotals(regularOtMinutes: 120),
        settings: const PayrollSettings(ordinaryOtMultiplier: 1.5),
      );
      expect(b.overtimeAmount, _peso(306.82));
    });
  });
}