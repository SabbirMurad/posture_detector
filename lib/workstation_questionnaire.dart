import 'package:flutter/material.dart';
import 'package:posture_detector/workstation_answers.dart';

/// Pre-camera questionnaire covering ROSA checklist items the camera can't
/// see (adjustability, glare, phone use, duration, etc.). Returns a
/// [WorkstationAnswers] via Navigator.pop when the user taps Continue.
class WorkstationQuestionnaire extends StatefulWidget {
  const WorkstationQuestionnaire({super.key});

  @override
  State<WorkstationQuestionnaire> createState() => _WorkstationQuestionnaireState();
}

class _WorkstationQuestionnaireState extends State<WorkstationQuestionnaire> {
  // Section A — Chair
  bool _chairHeightAdjustable = true;
  bool _enoughUnderDeskSpace = true;
  SeatDepthFit _seatDepthFit = SeatDepthFit.ok;
  bool _seatPanAdjustable = true;
  bool _armrestAdjustable = true;
  bool _armrestHardDamaged = false;
  bool _armrestTooWide = false;
  bool _backrestAdjustable = true;
  bool _workSurfaceTooHigh = false;

  // Section B — Monitor & Telephone
  bool _monitorAdjustable = true;
  bool _neckTwistOver30 = false;
  bool _monitorTooFar = false;
  bool _screenGlare = false;
  bool _hasDocumentHolder = true;
  PhoneUsage _phoneUsage = PhoneUsage.none;
  bool _phoneCradleNeckShoulder = false;
  bool _hasHandsFreeOption = true;

  // Section C — Mouse & Keyboard
  bool _mouseKeyboardDifferentSurfaces = false;
  bool _mousePinchGrip = false;
  bool _mousePalmrest = false;
  bool _mouseAdjustable = true;
  bool _keyboardDeviation = false;
  bool _keyboardTooHigh = false;
  bool _reachingOverhead = false;
  bool _keyboardPlatformAdjustable = true;

  // Duration
  DeskDuration _deskDuration = DeskDuration.medium;

  void _continue() {
    Navigator.of(context).pop(
      WorkstationAnswers(
        chairHeightNonAdjustable: !_chairHeightAdjustable,
        insufficientUnderDeskSpace: !_enoughUnderDeskSpace,
        seatDepthFit: _seatDepthFit,
        seatPanNonAdjustable: !_seatPanAdjustable,
        armrestNonAdjustable: !_armrestAdjustable,
        armrestHardDamaged: _armrestHardDamaged,
        armrestTooWide: _armrestTooWide,
        backrestNonAdjustable: !_backrestAdjustable,
        workSurfaceTooHigh: _workSurfaceTooHigh,
        monitorNonAdjustable: !_monitorAdjustable,
        neckTwistOver30: _neckTwistOver30,
        monitorTooFar: _monitorTooFar,
        screenGlare: _screenGlare,
        noDocumentHolder: !_hasDocumentHolder,
        phoneUsage: _phoneUsage,
        phoneCradleNeckShoulder: _phoneCradleNeckShoulder,
        noHandsFreeOption: !_hasHandsFreeOption,
        mouseKeyboardDifferentSurfaces: _mouseKeyboardDifferentSurfaces,
        mousePinchGrip: _mousePinchGrip,
        mousePalmrest: _mousePalmrest,
        mouseNonAdjustable: !_mouseAdjustable,
        keyboardDeviation: _keyboardDeviation,
        keyboardTooHigh: _keyboardTooHigh,
        reachingOverhead: _reachingOverhead,
        keyboardPlatformNonAdjustable: !_keyboardPlatformAdjustable,
        deskDuration: _deskDuration,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Workstation Setup')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const _SectionHeader('Chair'),
          _BoolQuestion(
            'Chair height is adjustable',
            _chairHeightAdjustable,
            (v) => setState(() => _chairHeightAdjustable = v),
          ),
          _BoolQuestion(
            'Enough room under the desk to cross your legs',
            _enoughUnderDeskSpace,
            (v) => setState(() => _enoughUnderDeskSpace = v),
          ),
          const SizedBox(height: 8),
          const Text('Seat pan depth (space behind your knees)', style: TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          SegmentedButton<SeatDepthFit>(
            segments: const [
              ButtonSegment(value: SeatDepthFit.ok, label: Text('~3 in (OK)')),
              ButtonSegment(value: SeatDepthFit.tooLong, label: Text('Too long')),
              ButtonSegment(value: SeatDepthFit.tooShort, label: Text('Too short')),
            ],
            selected: {_seatDepthFit},
            onSelectionChanged: (s) => setState(() => _seatDepthFit = s.first),
          ),
          _BoolQuestion(
            'Seat pan depth is adjustable',
            _seatPanAdjustable,
            (v) => setState(() => _seatPanAdjustable = v),
          ),
          _BoolQuestion(
            'Armrests are adjustable',
            _armrestAdjustable,
            (v) => setState(() => _armrestAdjustable = v),
          ),
          _BoolQuestion(
            'Armrest surface is hard or damaged',
            _armrestHardDamaged,
            (v) => setState(() => _armrestHardDamaged = v),
          ),
          _BoolQuestion(
            'Armrests are too wide (push elbows outward)',
            _armrestTooWide,
            (v) => setState(() => _armrestTooWide = v),
          ),
          _BoolQuestion(
            'Backrest is adjustable',
            _backrestAdjustable,
            (v) => setState(() => _backrestAdjustable = v),
          ),
          _BoolQuestion(
            'Desk/work surface is too high (shoulders shrug)',
            _workSurfaceTooHigh,
            (v) => setState(() => _workSurfaceTooHigh = v),
          ),

          const _SectionHeader('Monitor & Telephone'),
          _BoolQuestion(
            'Monitor position is adjustable',
            _monitorAdjustable,
            (v) => setState(() => _monitorAdjustable = v),
          ),
          _BoolQuestion(
            'You twist your neck more than 30° to view the monitor',
            _neckTwistOver30,
            (v) => setState(() => _neckTwistOver30 = v),
          ),
          _BoolQuestion(
            'Monitor is farther than arm\'s length away (>75cm)',
            _monitorTooFar,
            (v) => setState(() => _monitorTooFar = v),
          ),
          _BoolQuestion(
            'There is glare on the screen',
            _screenGlare,
            (v) => setState(() => _screenGlare = v),
          ),
          _BoolQuestion(
            'You have a document holder for paper references',
            _hasDocumentHolder,
            (v) => setState(() => _hasDocumentHolder = v),
          ),
          const SizedBox(height: 8),
          const Text('Desk phone usage', style: TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          SegmentedButton<PhoneUsage>(
            segments: const [
              ButtonSegment(value: PhoneUsage.none, label: Text('Don\'t use')),
              ButtonSegment(value: PhoneUsage.headsetOrOneHand, label: Text('Headset/1-hand')),
              ButtonSegment(value: PhoneUsage.reachFar, label: Text('Reach far')),
            ],
            selected: {_phoneUsage},
            onSelectionChanged: (s) => setState(() => _phoneUsage = s.first),
          ),
          if (_phoneUsage != PhoneUsage.none) ...[
            _BoolQuestion(
              'You cradle the phone between ear and shoulder',
              _phoneCradleNeckShoulder,
              (v) => setState(() => _phoneCradleNeckShoulder = v),
            ),
            _BoolQuestion(
              'You have a hands-free option (headset/speakerphone)',
              _hasHandsFreeOption,
              (v) => setState(() => _hasHandsFreeOption = v),
            ),
          ],

          const _SectionHeader('Mouse & Keyboard'),
          _BoolQuestion(
            'Mouse and keyboard are on different surfaces/heights',
            _mouseKeyboardDifferentSurfaces,
            (v) => setState(() => _mouseKeyboardDifferentSurfaces = v),
          ),
          _BoolQuestion(
            'You use a pinch grip on the mouse',
            _mousePinchGrip,
            (v) => setState(() => _mousePinchGrip = v),
          ),
          _BoolQuestion(
            'There is a palm rest in front of the mouse',
            _mousePalmrest,
            (v) => setState(() => _mousePalmrest = v),
          ),
          _BoolQuestion(
            'Mouse position is adjustable',
            _mouseAdjustable,
            (v) => setState(() => _mouseAdjustable = v),
          ),
          _BoolQuestion(
            'Wrists bend sideways (deviate) while typing',
            _keyboardDeviation,
            (v) => setState(() => _keyboardDeviation = v),
          ),
          _BoolQuestion(
            'Keyboard is too high (shoulders shrug)',
            _keyboardTooHigh,
            (v) => setState(() => _keyboardTooHigh = v),
          ),
          _BoolQuestion(
            'You frequently reach overhead for items',
            _reachingOverhead,
            (v) => setState(() => _reachingOverhead = v),
          ),
          _BoolQuestion(
            'Keyboard platform/tray is adjustable',
            _keyboardPlatformAdjustable,
            (v) => setState(() => _keyboardPlatformAdjustable = v),
          ),

          const _SectionHeader('Daily Duration'),
          const Text(
            'How long do you typically work continuously at this desk?',
            style: TextStyle(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          SegmentedButton<DeskDuration>(
            segments: const [
              ButtonSegment(value: DeskDuration.short, label: Text('< 30 min')),
              ButtonSegment(value: DeskDuration.medium, label: Text('30-60 min')),
              ButtonSegment(value: DeskDuration.long, label: Text('> 1 hour')),
            ],
            selected: {_deskDuration},
            onSelectionChanged: (s) => setState(() => _deskDuration = s.first),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: _continue,
              child: const Text('Continue', style: TextStyle(fontSize: 17)),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}

class _BoolQuestion extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _BoolQuestion(this.label, this.value, this.onChanged);

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      value: value,
      onChanged: onChanged,
    );
  }
}
