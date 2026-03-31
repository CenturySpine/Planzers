import 'package:go_router/go_router.dart';
import 'package:planzers/features/auth/auth_gate.dart';
import 'package:planzers/features/auth/sign_in_page.dart';
import 'package:planzers/features/trips/presentation/trips_page.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  routes: <RouteBase>[
    GoRoute(
      path: '/',
      builder: (context, state) => const AuthGate(),
    ),
    GoRoute(
      path: '/sign-in',
      builder: (context, state) => const SignInPage(),
    ),
    GoRoute(
      path: '/trips',
      builder: (context, state) => const TripsPage(),
    ),
  ],
);
