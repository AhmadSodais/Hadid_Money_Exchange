import '../../data/repositories/auth_repository_impl.dart';
import '../../data/repositories/audit_repository_impl.dart';
import '../../data/repositories/customer_repository_impl.dart';
import '../../data/repositories/employee_repository_impl.dart';
import '../../data/repositories/expense_repository_impl.dart';
import '../../data/repositories/inventory_repository_impl.dart';
import '../../data/repositories/lookup_repository_impl.dart';
import '../../data/repositories/order_repository_impl.dart';
import '../../data/repositories/product_repository_impl.dart';
import '../../data/repositories/purchase_repository_impl.dart';
import '../../data/repositories/supplier_repository_impl.dart';
import '../../data/repositories/warehouse_repository_impl.dart';
import '../../domain/repositories/repositories.dart';

/// Simple service locator for Hadid dependencies.
class ServiceLocator {
  ServiceLocator._();

  static final ServiceLocator instance = ServiceLocator._();

  late final ProductRepository products = ProductRepositoryImpl();
  late final LookupRepository lookups = LookupRepositoryImpl();
  late final CustomerRepository customers = CustomerRepositoryImpl();
  late final SupplierRepository suppliers = SupplierRepositoryImpl();
  late final InventoryRepository inventory = InventoryRepositoryImpl();
  late final OrderRepository orders = OrderRepositoryImpl();
  late final PurchaseRepository purchases = PurchaseRepositoryImpl();
  late final ExpenseRepository expenses = ExpenseRepositoryImpl();
  late final WarehouseRepository warehouses = WarehouseRepositoryImpl();
  late final EmployeeRepository employees = EmployeeRepositoryImpl();
  late final AuditRepository audit = AuditRepositoryImpl();
  late final AuthRepository auth = AuthRepositoryImpl();
}
