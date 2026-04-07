import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:planzers/features/auth/auth_gate.dart';
import 'package:planzers/features/auth/sign_in_page.dart';
import 'package:planzers/features/trips/data/trip.dart';
import 'package:planzers/features/trips/presentation/invite_join_page.dart';
import 'package:planzers/features/trips/presentation/trip_details_page.dart';
import 'package:planzers/features/trips/presentation/trips_page.dart';

final GoRouter appRouter = GoRouter(
  routes: <RouteBase>[
    GoRoute(
      path: '/',
      builder: (context, state) => const AuthGate(),
    ),
    GoRoute(
      path: '/sign-in',
      builder: (context, state) {
        final redirect = state.uri.queryParameters['redirect'];
        return SignInPage(redirectAfterSignIn: redirect);
      },
    ),
    GoRoute(
      path: '/invite',
      builder: (context, state) {
        final tripId = state.uri.queryParameters['tripId'] ?? '';
        final token = state.uri.queryParameters['token'] ?? '';
        return InviteJoinPage(tripId: tripId, token: token);
      },
    ),
    GoRoute(
      path: '/trips',
      builder: (context, state) => const TripsPage(),
    ),
    GoRoute(
      path: '/trips/:tripId',
      builder: (context, state) {
        final extra = state.extra;
        final trip = extra is Trip ? extra : null;
        if (trip == null) {
          return const Scaffold(
            body: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Voyage introuvable (donnees manquantes).',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        return TripDetailsPage(trip: trip);
      },
    ),
  ],
);
