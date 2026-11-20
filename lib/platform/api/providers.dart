/// Riverpod wiring for the API client, so a feature reads `ref.watch(expensesApiProvider)` and gets
/// a data source backed by the one configured client — base URL, token interceptor and all.
///
/// [apiConfigProvider] and [authTokenStoreProvider] are the two seams a host app overrides: point
/// the base URL at the right environment in `main()` via a `ProviderScope(overrides: [...])`, and
/// swap the token store for an in-memory one in a test. Everything else derives from them.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'auth_token_store.dart';
import 'resources/assistant_api.dart';
import 'resources/auth_api.dart';
import 'resources/budgets_api.dart';
import 'resources/categories_api.dart';
import 'resources/expenses_api.dart';
import 'resources/fixed_expenses_api.dart';
import 'resources/items_api.dart';
import 'resources/plans_api.dart';
import 'resources/reports_api.dart';
import 'resources/summary_api.dart';
import 'resources/units_api.dart';

/// The backend base URL.
///
/// Set it at build/run time with `--dart-define=API_URL=...`, which is how a physical device
/// reaches the backend on the developer's machine (a phone cannot use `localhost` or the Android
/// emulator's `10.0.2.2`; it needs the Mac's LAN IP, e.g. `http://192.168.1.4:27707`).
///
/// The default is the deployed Heroku backend, so a release build points at production with no
/// define. For local development, pass `--dart-define=API_URL=...` (see `make env`/`make run`)
/// to reach a backend on the developer's machine. A test or `main()` can still override this
/// provider directly.
const _defaultApiUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'https://kise-app-1d266401bf6a.herokuapp.com',
);

final apiConfigProvider = Provider<ApiConfig>(
  (ref) => const ApiConfig(baseUrl: _defaultApiUrl),
);

final authTokenStoreProvider = Provider<AuthTokenStore>(
  (ref) => SecureAuthTokenStore(),
);

final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(
    config: ref.watch(apiConfigProvider),
    tokenStore: ref.watch(authTokenStoreProvider),
  ),
);

final authApiProvider = Provider<AuthApi>(
  (ref) => AuthApi(ref.watch(apiClientProvider), ref.watch(authTokenStoreProvider)),
);

final categoriesApiProvider = Provider<CategoriesApi>(
  (ref) => CategoriesApi(ref.watch(apiClientProvider)),
);

final expensesApiProvider = Provider<ExpensesApi>(
  (ref) => ExpensesApi(ref.watch(apiClientProvider)),
);

final unitsApiProvider = Provider<UnitsApi>(
  (ref) => UnitsApi(ref.watch(apiClientProvider)),
);

final itemsApiProvider = Provider<ItemsApi>(
  (ref) => ItemsApi(ref.watch(apiClientProvider)),
);

final itemUsageReportsApiProvider = Provider<ItemUsageReportsApi>(
  (ref) => ItemUsageReportsApi(ref.watch(apiClientProvider)),
);

final monthlySummaryApiProvider = Provider<MonthlySummaryApi>(
  (ref) => MonthlySummaryApi(ref.watch(apiClientProvider)),
);

final fixedExpensesApiProvider = Provider<FixedExpensesApi>(
  (ref) => FixedExpensesApi(ref.watch(apiClientProvider)),
);

final budgetsApiProvider = Provider<BudgetsApi>(
  (ref) => BudgetsApi(ref.watch(apiClientProvider)),
);

final assistantApiProvider = Provider<AssistantApi>(
  (ref) => AssistantApi(ref.watch(apiClientProvider)),
);

final plansApiProvider = Provider<PlansApi>((ref) => PlansApi(ref.watch(apiClientProvider)));
