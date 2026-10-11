import '../../core/errors/result.dart';
import '../../data/models/auth_models.dart';

abstract class AuthRepository {
  Future<Result<AppUserModel?>> login(String username, String password);
  Future<Result<AppUserModel?>> getUserById(int id);
  Future<Result<List<AppUserModel>>> listUsers();
  Future<Result<AppUserModel>> createUser({
    required String username,
    required String password,
    required String displayName,
    required int roleId,
    int? employeeId,
  });
  Future<Result<AppUserModel>> updateUser({
    required int id,
    String? username,
    String? password,
    String? displayName,
    int? roleId,
    int? employeeId,
    bool? isActive,
  });
  Future<Result<void>> deleteUser(int id);

  Future<Result<List<RoleModel>>> listRoles();
  Future<Result<RoleModel>> getRoleById(int id);
  Future<Result<RoleModel>> createRole({
    required String name,
    String? description,
    List<String>? permissions,
  });
  Future<Result<RoleModel>> updateRole({
    required int id,
    String? name,
    String? description,
    List<String>? permissions,
  });
  Future<Result<void>> deleteRole(int id);
  Future<Result<void>> setRolePermissions(int roleId, List<String> permissions);

  /// Whether local username/password login is required.
  Future<bool> isAuthEnabled();

  /// Enable login: create admin + store recovery code hash.
  Future<Result<AppUserModel>> enableAuth({
    required String username,
    required String password,
    required String displayName,
    required String recoveryCode,
    int? roleId,
  });

  /// Enable login using an existing user (optional password update + role).
  Future<Result<AppUserModel>> enableAuthForExistingUser({
    required int userId,
    required String recoveryCode,
    int? roleId,
    String? newPassword,
  });

  /// Disable login requirement (open access).
  Future<Result<void>> disableAuth();

  /// Reset password using the recovery code set when auth was enabled.
  Future<Result<void>> resetPasswordWithRecovery({
    required String recoveryCode,
    required String newPassword,
    String? username,
  });
}
