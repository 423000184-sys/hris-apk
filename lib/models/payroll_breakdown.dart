// lib/models/payroll_breakdown.dart

/// Value object na naglalaman ng lahat ng computed payroll figures
/// para sa isang employee sa isang period (usually 1 month).
///
/// Ginagamit ito ng [PayrollCalculator.compute] at ng ReportsScreen.
class PayrollBreakdown {
  // ─── EARNINGS ────────────────────────────────────────────────
  final double basicSalary;
  final double allowances;
  final double dailyRate;
  final double overtimePay;
  final double grossPay;

  // ─── GOVERNMENT DEDUCTIONS ───────────────────────────────────
  final double sss;
  final double philhealth;
  final double pagibig;
  final double withholdingTax;

  // ─── ATTENDANCE / ABSENCE ────────────────────────────────────
  final double absenceDeduction;
  final int absentDays;
  final int workingDays;
  final int presentDays;

  // ─── TIME LOGS (raw minutes) ─────────────────────────────────
  final int workRawMinutes;
  final int workLunchMinutes;
  final int workNetMinutes;
  final int workOvertimeMinutes;
  final int daysWithLogs;
  final int daysWithLunchApplied;

  // ─── NET ─────────────────────────────────────────────────────
  final double netPay;

  // ─── BENEFITS (accrued, not deducted) ────────────────────────
  final double thirteenthMonth;
  final double silCredits;

  const PayrollBreakdown({
    this.basicSalary = 0,
    this.allowances = 0,
    this.dailyRate = 0,
    this.overtimePay = 0,
    this.grossPay = 0,
    this.sss = 0,
    this.philhealth = 0,
    this.pagibig = 0,
    this.withholdingTax = 0,
    this.absenceDeduction = 0,
    this.absentDays = 0,
    this.workingDays = 0,
    this.presentDays = 0,
    this.workRawMinutes = 0,
    this.workLunchMinutes = 0,
    this.workNetMinutes = 0,
    this.workOvertimeMinutes = 0,
    this.daysWithLogs = 0,
    this.daysWithLunchApplied = 0,
    this.netPay = 0,
    this.thirteenthMonth = 0,
    this.silCredits = 0,
  });

  /// Default empty — ginagamit sa ReportsScreen bago mag-load.
  static const PayrollBreakdown empty = PayrollBreakdown();

  // ─── COMPUTED GETTERS ────────────────────────────────────────

  /// Total ng lahat ng deductions (gov't + absence).
  double get totalDeductions =>
      sss + philhealth + pagibig + withholdingTax + absenceDeduction;

  /// Total ng government remittances lang (walang absence).
  double get governmentTotal => sss + philhealth + pagibig + withholdingTax;

  /// Total accrued benefits (13th month + SIL).
  double get totalBenefits => thirteenthMonth + silCredits;

  // ─── COPY WITH ───────────────────────────────────────────────
  PayrollBreakdown copyWith({
    double? basicSalary,
    double? allowances,
    double? dailyRate,
    double? overtimePay,
    double? grossPay,
    double? sss,
    double? philhealth,
    double? pagibig,
    double? withholdingTax,
    double? absenceDeduction,
    int? absentDays,
    int? workingDays,
    int? presentDays,
    int? workRawMinutes,
    int? workLunchMinutes,
    int? workNetMinutes,
    int? workOvertimeMinutes,
    int? daysWithLogs,
    int? daysWithLunchApplied,
    double? netPay,
    double? thirteenthMonth,
    double? silCredits,
  }) {
    return PayrollBreakdown(
      basicSalary: basicSalary ?? this.basicSalary,
      allowances: allowances ?? this.allowances,
      dailyRate: dailyRate ?? this.dailyRate,
      overtimePay: overtimePay ?? this.overtimePay,
      grossPay: grossPay ?? this.grossPay,
      sss: sss ?? this.sss,
      philhealth: philhealth ?? this.philhealth,
      pagibig: pagibig ?? this.pagibig,
      withholdingTax: withholdingTax ?? this.withholdingTax,
      absenceDeduction: absenceDeduction ?? this.absenceDeduction,
      absentDays: absentDays ?? this.absentDays,
      workingDays: workingDays ?? this.workingDays,
      presentDays: presentDays ?? this.presentDays,
      workRawMinutes: workRawMinutes ?? this.workRawMinutes,
      workLunchMinutes: workLunchMinutes ?? this.workLunchMinutes,
      workNetMinutes: workNetMinutes ?? this.workNetMinutes,
      workOvertimeMinutes: workOvertimeMinutes ?? this.workOvertimeMinutes,
      daysWithLogs: daysWithLogs ?? this.daysWithLogs,
      daysWithLunchApplied:
      daysWithLunchApplied ?? this.daysWithLunchApplied,
      netPay: netPay ?? this.netPay,
      thirteenthMonth: thirteenthMonth ?? this.thirteenthMonth,
      silCredits: silCredits ?? this.silCredits,
    );
  }

  @override
  String toString() => 'PayrollBreakdown('
      'basic=$basicSalary, allow=$allowances, daily=$dailyRate, '
      'gross=$grossPay, sss=$sss, ph=$philhealth, pi=$pagibig, '
      'tax=$withholdingTax, absent=$absentDays, net=$netPay)';
}