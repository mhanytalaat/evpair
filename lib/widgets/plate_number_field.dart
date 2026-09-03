import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/ps_ev_theme.dart';
import '../utils/plate_number_validator.dart';

/// Segmented Egyptian-style plate number input:
///   - ONE field for the digits (3-4 numbers), on the LEFT.
///   - Three SEPARATE single-character boxes for the letters, one per
///     letter, on the RIGHT (leave the 3rd one blank for a Giza-style
///     2-letter plate).
///
/// This matches how a real Egyptian plate reads: letters on the right,
/// numbers on the left (the previous single free-text field required
/// typing numbers-then-letters left-to-right in one box, which didn't
/// match the physical plate layout at all). Letters are forced to
/// uppercase English (A-Z) only, per requirement - Arabic input is not
/// accepted here (though PlateNumberValidator itself still recognizes
/// Arabic letters for any legacy/free-text data already stored).
///
/// Typing a letter automatically advances focus to the next letter box;
/// backspacing on an empty box moves focus back to the previous one -
/// standard OTP-style segmented input behavior.
class PlateNumberField extends StatefulWidget {
  /// Existing plate in normalized form (e.g. "123ABC"), if editing.
  final String? initialValue;
  final ValueChanged<String> onChanged;
  const PlateNumberField({super.key, this.initialValue, required this.onChanged});

  @override
  State<PlateNumberField> createState() => _PlateNumberFieldState();
}

class _PlateNumberFieldState extends State<PlateNumberField> {
  late final TextEditingController _digitsCtrl;
  late final List<TextEditingController> _letterCtrls;
  late final List<FocusNode> _letterFocusNodes;

  @override
  void initState() {
    super.initState();
    final split = widget.initialValue == null ? null : PlateNumberValidator.split(widget.initialValue!);
    _digitsCtrl = TextEditingController(text: split?.digits ?? '');
    final letters = split?.letters ?? '';
    _letterCtrls = List.generate(3, (i) => TextEditingController(text: i < letters.length ? letters[i] : ''));
    _letterFocusNodes = List.generate(3, (_) => FocusNode());
    _digitsCtrl.addListener(_emitChange);
    for (final c in _letterCtrls) {
      c.addListener(_emitChange);
    }
  }

  @override
  void dispose() {
    _digitsCtrl.dispose();
    for (final c in _letterCtrls) {
      c.dispose();
    }
    for (final f in _letterFocusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _emitChange() {
    final letters = _letterCtrls.map((c) => c.text).join();
    widget.onChanged(PlateNumberValidator.combine(digits: _digitsCtrl.text, letters: letters));
  }

  void _onLetterChanged(int index, String value) {
    if (value.isNotEmpty && index < 2) {
      _letterFocusNodes[index + 1].requestFocus();
    }
  }

  Widget _letterBox(int index) {
    return SizedBox(
      width: 46,
      child: KeyboardListener(
        focusNode: FocusNode(skipTraversal: true),
        onKeyEvent: (event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.backspace &&
              _letterCtrls[index].text.isEmpty &&
              index > 0) {
            _letterFocusNodes[index - 1].requestFocus();
          }
        },
        child: TextField(
          controller: _letterCtrls[index],
          focusNode: _letterFocusNodes[index],
          textAlign: TextAlign.center,
          maxLength: 1,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z]')),
            UpperCaseTextFormatter(),
          ],
          decoration: const InputDecoration(counterText: '', contentPadding: EdgeInsets.symmetric(vertical: 14)),
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, letterSpacing: 1),
          onChanged: (v) => _onLetterChanged(index, v),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Digits on the LEFT, letter boxes on the RIGHT - matches the
        // real plate layout (letters on the right side, numbers on the
        // left).
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: _digitsCtrl,
                keyboardType: TextInputType.number,
                maxLength: 4,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(counterText: '', hintText: '1234'),
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, letterSpacing: 1),
              ),
            ),
            const SizedBox(width: 10),
            Container(width: 1.5, height: 48, color: PsEvColors.slate200, margin: const EdgeInsets.only(top: 2)),
            const SizedBox(width: 10),
            _letterBox(0),
            const SizedBox(width: 6),
            _letterBox(1),
            const SizedBox(width: 6),
            _letterBox(2),
          ],
        ),
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text(
            'Numbers on the left, letters on the right (English only) - '
            'leave the 3rd letter box empty for a Giza-style 2-letter plate.',
            style: TextStyle(fontSize: 11, color: PsEvColors.mutedText),
          ),
        ),
      ],
    );
  }
}

/// Forces every keystroke to uppercase as it's typed, so a lowercase "a"
/// on a physical keyboard still shows/stores as "A" without needing
/// textCapitalization (which only affects the on-screen keyboard's
/// initial case, not what's actually typed).
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
