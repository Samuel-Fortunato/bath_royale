import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

int randomAccent() => Random().nextInt(0x1000000);

/// HSV surface plus exact RGB input, without an external picker dependency.
class AccentPicker extends StatefulWidget {
  const AccentPicker({super.key, required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;
  @override
  State<AccentPicker> createState() => _AccentPickerState();
}

class _AccentPickerState extends State<AccentPicker> {
  late HSVColor hsv;
  late final TextEditingController hex;
  @override
  void initState() {
    super.initState();
    hsv = HSVColor.fromColor(Color(0xff000000 | widget.value));
    hex = TextEditingController(
      text: widget.value.toRadixString(16).padLeft(6, '0').toUpperCase(),
    );
  }

  @override
  void didUpdateWidget(AccentPicker old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      hsv = HSVColor.fromColor(Color(0xff000000 | widget.value));
      final next = widget.value.toRadixString(16).padLeft(6, '0').toUpperCase();
      if (hex.text.toUpperCase() != next) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            hex.text = next;
          }
        });
      }
    }
  }

  @override
  void dispose() {
    hex.dispose();
    super.dispose();
  }

  void change(HSVColor next) {
    setState(() => hsv = next);
    widget.onChanged(next.toColor().toARGB32() & 0xffffff);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          const Expanded(child: Text('Cor do trono')),
          IconButton(
            tooltip: 'Outra cor aleatória',
            icon: const Icon(Icons.shuffle),
            onPressed: () => widget.onChanged(randomAccent()),
          ),
        ],
      ),
      LayoutBuilder(
        builder: (context, box) {
          void select(Offset p) => change(
            hsv
                .withSaturation((p.dx / box.maxWidth).clamp(0, 1))
                .withValue(1 - (p.dy / 130).clamp(0, 1)),
          );
          return Semantics(
            label: 'Saturação e luminosidade da cor',
            child: GestureDetector(
              onTapDown: (e) => select(e.localPosition),
              onPanUpdate: (e) => select(e.localPosition),
              child: Container(
                height: 130,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    colors: [
                      Colors.white,
                      HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor(),
                    ],
                  ),
                ),
                child: Stack(
                  children: [
                    const Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.black],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: (box.maxWidth * hsv.saturation - 9).clamp(
                        0,
                        box.maxWidth - 18,
                      ),
                      top: (130 * (1 - hsv.value) - 9).clamp(0, 112),
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: const [BoxShadow(blurRadius: 2)],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
      Slider(
        value: hsv.hue,
        max: 360,
        label: 'Tonalidade',
        semanticFormatterCallback: (v) => 'Tonalidade ${v.round()}',
        onChanged: (v) => change(hsv.withHue(v)),
      ),
      TextFormField(
        controller: hex,
        maxLength: 6,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F]')),
        ],
        decoration: const InputDecoration(
          labelText: 'Cor RGB',
          prefixText: '#',
          counterText: '',
        ),
        onChanged: (v) {
          if (v.length == 6) widget.onChanged(int.parse(v, radix: 16));
        },
      ),
    ],
  );
}
