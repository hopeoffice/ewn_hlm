import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Ported from #ad-carousel in index.html / style.css — 3 slides,
/// auto-advances every 10s, with a dot indicator.
class BannerCarousel extends StatefulWidget {
  final VoidCallback? onSearchTap;
  final ValueChanged<String>? onCategoryTap;

  const BannerCarousel({super.key, this.onSearchTap, this.onCategoryTap});

  @override
  State<BannerCarousel> createState() => _BannerCarouselState();
}

class _BannerCarouselState extends State<BannerCarousel> {
  final _controller = PageController();
  Timer? _timer;
  int _page = 0;

  static const _slides = [
    _BannerData(
      eyebrow: '🌟 Ewn Hlm',
      title: 'ሕልምዎ እውን የሚሆንበት\nየዲጂታል ገበያ!!',
      cta: 'አሁን ይሸምቱ →',
      gradient: [AppTheme.brand, AppTheme.brandLight],
    ),
    _BannerData(
      eyebrow: '🔥 ልዩ ቅናሽ',
      title: 'ምርጥ ምርቶች\nበቅናሽ ዋጋ!!',
      cta: 'ይመልከቱ →',
      gradient: [Color(0xFF1E3A5F), Color(0xFF3B82F6)],
      category: 'beauty_health',
    ),
    _BannerData(
      eyebrow: '📱 አዲስ ምርቶች',
      title: 'የቴክኖሎጂ ምርቶች\nአዲስ ክምችት!!',
      cta: 'አሁን ይሸምቱ →',
      gradient: [Color(0xFF78350F), Color(0xFFF97316)],
      category: 'phones',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted) return;
      final next = (_page + 1) % _slides.length;
      _controller.animateToPage(next,
          duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 140,
          child: PageView.builder(
            controller: _controller,
            onPageChanged: (i) => setState(() => _page = i),
            itemCount: _slides.length,
            itemBuilder: (context, i) {
              final s = _slides[i];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppTheme.radius),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: s.gradient,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(s.eyebrow, style: const TextStyle(color: Colors.white, fontSize: 13)),
                      const SizedBox(height: 6),
                      Text(s.title,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, height: 1.3)),
                      const SizedBox(height: 10),
                      GestureDetector(
                        onTap: () {
                          if (s.category != null) {
                            widget.onCategoryTap?.call(s.category!);
                          } else {
                            widget.onSearchTap?.call();
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(s.cta,
                              style: TextStyle(color: s.gradient.first, fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_slides.length, (i) {
            final active = i == _page;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: active ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: active ? AppTheme.accent : AppTheme.border,
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _BannerData {
  final String eyebrow;
  final String title;
  final String cta;
  final List<Color> gradient;
  final String? category;
  const _BannerData({
    required this.eyebrow,
    required this.title,
    required this.cta,
    required this.gradient,
    this.category,
  });
}
