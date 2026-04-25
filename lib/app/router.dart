import 'package:go_router/go_router.dart';
import 'package:planerz/features/about/presentation/about_page.dart';
import 'package:planerz/features/account/presentation/account_page.dart';
import 'package:planerz/features/auth/auth_gate.dart';
import 'package:planerz/features/auth/sign_in_page.dart';
import 'package:planerz/features/legal/presentation/legal_information_page.dart';
import 'package:planerz/features/trips/presentation/invite_join_page.dart';
import 'package:planerz/features/activities/presentation/trip_activities_page.dart';
import 'package:planerz/features/activities/presentation/trip_activity_detail_page.dart';
import 'package:planerz/features/expenses/presentation/trip_expenses_page.dart';
import 'package:planerz/features/messaging/presentation/trip_messaging_page.dart';
import 'package:planerz/features/meals/presentation/trip_meal_details_page.dart';
import 'package:planerz/features/meals/presentation/trip_meals_page.dart';
import 'package:planerz/features/rooms/presentation/trip_rooms_page.dart';
import 'package:planerz/features/shopping/presentation/trip_shopping_page.dart';
import 'package:planerz/features/trips/presentation/trip_overview_page.dart';
import 'package:planerz/features/trips/presentation/trip_announcements_page.dart';
import 'package:planerz/features/trips/presentation/trip_participants_page.dart';
import 'package:planerz/features/trips/presentation/trip_participants_permissions_page.dart';
import 'package:planerz/features/trips/presentation/trip_expenses_permissions_page.dart';
import 'package:planerz/features/trips/presentation/trip_activities_permissions_page.dart';
import 'package:planerz/features/trips/presentation/trip_general_permissions_page.dart';
import 'package:planerz/features/trips/presentation/trip_shopping_permissions_page.dart';
import 'package:planerz/features/trips/presentation/trip_settings_page.dart';
import 'package:planerz/features/trips/presentation/trip_shell_page.dart';
import 'package:planerz/features/trips/presentation/trip_member_preferences_page.dart';
import 'package:planerz/features/trips/presentation/trips_page.dart';
import 'package:planerz/features/cupidon/presentation/cupidon_space_page.dart';

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
      path: '/account/cupidon',
      builder: (context, state) => const CupidonSpacePage(),
    ),
    GoRoute(
      path: LegalInformationPage.routePath,
      builder: (context, state) => const LegalInformationPage(),
    ),
    GoRoute(
      path: AboutPage.routePath,
      builder: (context, state) => const AboutPage(),
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
        GoRoute(
          path: 'meals/new',
          builder: (context, state) => TripMealDetailsPage(
            tripId: state.pathParameters['tripId']!,
          ),
        ),
        GoRoute(
          path: 'meals/:mealId',
          builder: (context, state) => TripMealDetailsPage(
            tripId: state.pathParameters['tripId']!,
            mealId: state.pathParameters['mealId']!,
          ),
        ),
        GoRoute(
          path: 'settings',
          builder: (context, state) => TripSettingsPage(
            tripId: state.pathParameters['tripId']!,
          ),
          routes: <RouteBase>[
            GoRoute(
              path: 'trip',
              builder: (context, state) => TripGeneralPermissionsPage(
                tripId: state.pathParameters['tripId']!,
              ),
            ),
            GoRoute(
              path: 'participants',
              builder: (context, state) => TripParticipantsPermissionsPage(
                tripId: state.pathParameters['tripId']!,
              ),
            ),
            GoRoute(
              path: 'expenses',
              builder: (context, state) => TripExpensesPermissionsPage(
                tripId: state.pathParameters['tripId']!,
              ),
            ),
            GoRoute(
              path: 'activities',
              builder: (context, state) => TripActivitiesPermissionsPage(
                tripId: state.pathParameters['tripId']!,
              ),
            ),
            GoRoute(
              path: 'shopping',
              builder: (context, state) => TripShoppingPermissionsPage(
                tripId: state.pathParameters['tripId']!,
              ),
            ),
          ],
        ),
        GoRoute(
          path: 'participants',
          builder: (context, state) => TripParticipantsPage(
            tripId: state.pathParameters['tripId']!,
          ),
        ),
        GoRoute(
          path: 'preferences',
          builder: (context, state) => TripMemberPreferencesPage(
            tripId: state.pathParameters['tripId']!,
          ),
        ),
        GoRoute(
          path: 'activities/:activityId',
          builder: (context, state) => TripActivityDetailPage(
            tripId: state.pathParameters['tripId']!,
            activityId: state.pathParameters['activityId']!,
          ),
        ),
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
            StatefulShellBranch(
              routes: <RouteBase>[
                GoRoute(
                  path: 'announcements',
                  builder: (context, state) => const TripAnnouncementsPage(),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ],
);
