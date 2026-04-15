import 'package:go_router/go_router.dart';
import 'package:planzers/features/account/presentation/account_page.dart';
import 'package:planzers/features/auth/auth_gate.dart';
import 'package:planzers/features/auth/sign_in_page.dart';
import 'package:planzers/features/trips/presentation/invite_join_page.dart';
import 'package:planzers/features/activities/presentation/trip_activities_page.dart';
import 'package:planzers/features/expenses/presentation/trip_expenses_page.dart';
import 'package:planzers/features/messaging/presentation/trip_messaging_page.dart';
import 'package:planzers/features/rooms/presentation/trip_rooms_page.dart';
import 'package:planzers/features/shopping/presentation/trip_shopping_page.dart';
import 'package:planzers/features/trips/presentation/trip_overview_page.dart';
import 'package:planzers/features/trips/presentation/trip_shell_page.dart';
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
      path: '/account',
      builder: (context, state) => const AccountPage(),
    ),
    GoRoute(
      path: '/trips/:tripId',
      redirect: (context, state) {
        final segs = state.uri.pathSegments;
        if (segs.length == 2) {
          return '/trips/${state.pathParameters['tripId']}/overview';
        }
        return null;
      },
      routes: <RouteBase>[
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) {
            final tripId = state.pathParameters['tripId']!;
            return TripShellPage(
              tripId: tripId,
              navigationShell: navigationShell,
            );
          },
          branches: <StatefulShellBranch>[
            StatefulShellBranch(
              routes: <RouteBase>[
                GoRoute(
                  path: 'overview',
                  builder: (context, state) => const TripOverviewPage(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: <RouteBase>[
                GoRoute(
                  path: 'messages',
                  builder: (context, state) => const TripMessagingPage(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: <RouteBase>[
                GoRoute(
                  path: 'expenses',
                  builder: (context, state) => const TripExpensesPage(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: <RouteBase>[
                GoRoute(
                  path: 'rooms',
                  builder: (context, state) => const TripRoomsPage(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: <RouteBase>[
                GoRoute(
                  path: 'cars',
                  builder: (context, state) => const TripCarsPage(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: <RouteBase>[
                GoRoute(
                  path: 'meals',
                  builder: (context, state) => const TripMealsPage(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: <RouteBase>[
                GoRoute(
                  path: 'activities',
                  builder: (context, state) => const TripActivitiesPage(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: <RouteBase>[
                GoRoute(
                  path: 'shopping',
                  builder: (context, state) => const TripShoppingPage(),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ],
);
