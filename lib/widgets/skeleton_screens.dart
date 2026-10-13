// lib/widgets/skeleton_screens.dart
import 'package:flutter/material.dart';
import 'skeleton_loader.dart';

// ═══════════════════════════════════════════════════════════════
// 🏠 DASHBOARD SKELETON
// ═══════════════════════════════════════════════════════════════
class DashboardSkeleton extends StatelessWidget {
  const DashboardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerBox(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: Row(
                children: [
                  SkeletonCircle(size: 44),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonText(width: 120, height: 10),
                        SizedBox(height: 6),
                        SkeletonText(width: 180, height: 14),
                      ],
                    ),
                  ),
                  SkeletonCircle(size: 24),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Hero card
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: SkeletonBlock(height: 180, radius: 24),
            ),
            const SizedBox(height: 24),

            // Quick stats (3 boxes)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Expanded(child: SkeletonBlock(height: 90, radius: 16)),
                  SizedBox(width: 12),
                  Expanded(child: SkeletonBlock(height: 90, radius: 16)),
                  SizedBox(width: 12),
                  Expanded(child: SkeletonBlock(height: 90, radius: 16)),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Section title
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: SkeletonText(width: 140, height: 14),
            ),
            const SizedBox(height: 12),

            // List items
            ...List.generate(
              3,
                  (i) => Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                child: SkeletonBlock(height: 80, radius: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 👤 PROFILE SKELETON
// ═══════════════════════════════════════════════════════════════
class ProfileSkeleton extends StatelessWidget {
  const ProfileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerBox(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          children: [
            // Header
            const SkeletonBlock(height: 80, radius: 0),
            const SizedBox(height: 20),

            // Profile card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.topCenter,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 44),
                    padding: const EdgeInsets.fromLTRB(16, 56, 16, 20),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: SkeletonColors.border(context),
                        width: 1.15,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Column(
                      children: [
                        SkeletonText(width: 160, height: 18),
                        SizedBox(height: 8),
                        SkeletonText(width: 100, height: 12),
                        SizedBox(height: 12),
                        SkeletonText(width: 120, height: 24),
                      ],
                    ),
                  ),
                  const SkeletonBlock(width: 88, height: 88, radius: 16),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Section label
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 28),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SkeletonText(width: 120, height: 12),
              ),
            ),
            const SizedBox(height: 10),

            // Detail rows
            ...List.generate(
              4,
                  (i) => Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: SkeletonBlock(height: 62, radius: 12),
              ),
            ),
            const SizedBox(height: 20),

            // Section label
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 28),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SkeletonText(width: 100, height: 12),
              ),
            ),
            const SizedBox(height: 10),

            // Settings rows
            ...List.generate(
              3,
                  (i) => Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: SkeletonBlock(height: 62, radius: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 📊 REPORTS SKELETON
// ═══════════════════════════════════════════════════════════════
class ReportsSkeleton extends StatelessWidget {
  const ReportsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerBox(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: SkeletonText(width: 160, height: 20),
            ),
            const SizedBox(height: 20),

            // Filter chips
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  SkeletonBlock(width: 80, height: 32, radius: 20),
                  SizedBox(width: 8),
                  SkeletonBlock(width: 100, height: 32, radius: 20),
                  SizedBox(width: 8),
                  SkeletonBlock(width: 70, height: 32, radius: 20),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Chart
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: SkeletonBlock(height: 200, radius: 16),
            ),
            const SizedBox(height: 20),

            // Data rows
            ...List.generate(
              5,
                  (i) => Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
                child: Row(
                  children: [
                    const SkeletonCircle(size: 40),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonText(height: 12),
                          SizedBox(height: 6),
                          SkeletonText(width: 120, height: 10),
                        ],
                      ),
                    ),
                    const SkeletonBlock(width: 60, height: 20, radius: 6),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 📋 LIST SKELETON (generic — for logs, history, etc.)
// ═══════════════════════════════════════════════════════════════
class ListSkeleton extends StatelessWidget {
  final int itemCount;

  const ListSkeleton({super.key, this.itemCount = 5});

  @override
  Widget build(BuildContext context) {
    return ShimmerBox(
      child: ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        itemCount: itemCount,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, __) => Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(
              color: SkeletonColors.border(context),
              width: 1.15,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const SkeletonCircle(size: 44),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonText(width: 160, height: 13),
                    SizedBox(height: 8),
                    SkeletonText(width: 220, height: 11),
                  ],
                ),
              ),
              const SkeletonBlock(width: 60, height: 24, radius: 8),
            ],
          ),
        ),
      ),
    );
  }
}