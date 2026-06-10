enum SeatDepthFit { ok, tooLong, tooShort }

enum PhoneUsage { none, headsetOrOneHand, reachFar }

enum DeskDuration { short, medium, long }

/// Manual answers to the ROSA checklist items the camera can't see.
/// Field names mirror the official ROSA form's +1/+2 modifiers.
class WorkstationAnswers {
  // Section A — Chair
  final bool chairHeightNonAdjustable;
  final bool insufficientUnderDeskSpace;
  final SeatDepthFit seatDepthFit;
  final bool seatPanNonAdjustable;
  final bool armrestNonAdjustable;
  final bool armrestHardDamaged;
  final bool armrestTooWide;
  final bool backrestNonAdjustable;
  final bool workSurfaceTooHigh;

  // Section B — Monitor & Telephone
  final bool monitorNonAdjustable;
  final bool neckTwistOver30;
  final bool monitorTooFar;
  final bool screenGlare;
  final bool noDocumentHolder;
  final PhoneUsage phoneUsage;
  final bool phoneCradleNeckShoulder;
  final bool noHandsFreeOption;

  // Section C — Mouse & Keyboard
  final bool mouseKeyboardDifferentSurfaces;
  final bool mousePinchGrip;
  final bool mousePalmrest;
  final bool mouseNonAdjustable;
  final bool keyboardDeviation;
  final bool keyboardTooHigh;
  final bool reachingOverhead;
  final bool keyboardPlatformNonAdjustable;

  // Daily duration — applies to chair, monitor/phone, and mouse/keyboard sections
  final DeskDuration deskDuration;

  const WorkstationAnswers({
    this.chairHeightNonAdjustable = false,
    this.insufficientUnderDeskSpace = false,
    this.seatDepthFit = SeatDepthFit.ok,
    this.seatPanNonAdjustable = false,
    this.armrestNonAdjustable = false,
    this.armrestHardDamaged = false,
    this.armrestTooWide = false,
    this.backrestNonAdjustable = false,
    this.workSurfaceTooHigh = false,
    this.monitorNonAdjustable = false,
    this.neckTwistOver30 = false,
    this.monitorTooFar = false,
    this.screenGlare = false,
    this.noDocumentHolder = false,
    this.phoneUsage = PhoneUsage.none,
    this.phoneCradleNeckShoulder = false,
    this.noHandsFreeOption = false,
    this.mouseKeyboardDifferentSurfaces = false,
    this.mousePinchGrip = false,
    this.mousePalmrest = false,
    this.mouseNonAdjustable = false,
    this.keyboardDeviation = false,
    this.keyboardTooHigh = false,
    this.reachingOverhead = false,
    this.keyboardPlatformNonAdjustable = false,
    this.deskDuration = DeskDuration.medium,
  });

  Map<String, dynamic> toMap() => {
    'chair_height_non_adjustable': chairHeightNonAdjustable,
    'insufficient_under_desk_space': insufficientUnderDeskSpace,
    'seat_depth_score': seatDepthFit == SeatDepthFit.ok ? 1 : 2,
    'seat_pan_non_adjustable': seatPanNonAdjustable,
    'armrest_non_adjustable': armrestNonAdjustable,
    'armrest_hard_damaged': armrestHardDamaged,
    'armrest_too_wide': armrestTooWide,
    'backrest_non_adjustable': backrestNonAdjustable,
    'work_surface_too_high': workSurfaceTooHigh,
    'monitor_non_adjustable': monitorNonAdjustable,
    'neck_twist_over_30': neckTwistOver30,
    'monitor_too_far': monitorTooFar,
    'screen_glare': screenGlare,
    'no_document_holder': noDocumentHolder,
    'phone_score': switch (phoneUsage) {
      PhoneUsage.none => 0,
      PhoneUsage.headsetOrOneHand => 1,
      PhoneUsage.reachFar => 2,
    },
    'phone_cradle_neck_shoulder': phoneCradleNeckShoulder,
    'no_hands_free_option': noHandsFreeOption,
    'mouse_keyboard_different_surfaces': mouseKeyboardDifferentSurfaces,
    'mouse_pinch_grip': mousePinchGrip,
    'mouse_palmrest': mousePalmrest,
    'mouse_non_adjustable': mouseNonAdjustable,
    'keyboard_deviation': keyboardDeviation,
    'keyboard_too_high': keyboardTooHigh,
    'reaching_overhead': reachingOverhead,
    'keyboard_platform_non_adjustable': keyboardPlatformNonAdjustable,
    'duration_modifier': switch (deskDuration) {
      DeskDuration.short => -1,
      DeskDuration.medium => 0,
      DeskDuration.long => 1,
    },
  };
}
