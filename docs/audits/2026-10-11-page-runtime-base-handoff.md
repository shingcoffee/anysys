# Page runtime: base-model gap and preview child guard

## Confirmed runtime chain

- Public GET: `PublicPagesController#show` → `PageRendering` → `PageContentGenerator`.
- Member GET: `Member::PagesController#show` → the same renderer. Generated forms submit to the canonical public UUID endpoint.
- Submission: `PublicPagesController#submit` → `Pages::PublicSubmission` → `Pages::FormParams` → `ActivityTracer` → generated entity activity → `EntityEntryContract` → persistence inside the submission savepoint.
- `new_model` creates `EntityEntry.build_for(bound_entity)`, not the class named by `extended_model`. `build_contract` declares the entity schema; `save_model` saves that contract. `EntityEntry` has no linked base-record association.
- The older `DetectAndRouteParams` / `PopulatePrimary` / `SaveAll` helpers are not emitted by the inspected current generators. They now reject base input at routing, assignment and persistence boundaries. `SaveAll` also treats a false contract save as failure and owns a savepoint so a failed bridge save rolls back the primary write inside an outer transaction.

## Base-model support gap

`extended_model` and its approved column catalog provide metadata, not a runtime write capability. The inspected chain has no base-record resolver, model-specific writable-field contract or authenticated base-record ownership policy. This audit does **not** establish complete base-field support in the builder.

Runtime base fields are excluded from renderable/submittable inputs. Nonempty or malformed `base[...]` submissions are rejected before activity execution. Supplying a matching entity slug, class/record identifier, `current_user_id`, `current_user_role`, or an authentication-shaped hash cannot enable base writes. Existing helpers do not merge base values into entity JSON or call `assign_attributes` on a supplied base model. Assignment/persistence also reject a physical ActiveRecord target other than `EntityEntry`, including a base contract's target when the base namespace is omitted.

A future adapter must define approved target types and writable fields, resolve the record through an explicit server-owned link, derive authority from the request-local `FlowchartRuntime::Authentication` credential, enforce tenant and member ownership, and validate/save through the target's contract in the submission transaction. Model approval alone is not authorization.

## Unpublished owner preview

`ActivityTracer` applies the runtime execution facade to direct flowchart executions as well as public submissions. The caller may supply an unpublished preview parent; the facade retains that parent's prepared definition. Children must still be accessible to the current tenant and launched, and use their effective tenant definitions. The parent is not looked up through a launched-only scope. Diagram/introspection calls through `ActivityClassBuilder` are outside this execution facade.

## Verification and documentation handoff

Regression specs cover unsupported base writes and unpublished-parent/eligible-child execution. No tests were run. Builder routes, controllers, editors, templates and artifact-write behavior were not changed. Reference docs were not edited by request; matching English and Simplified Chinese runtime pages still need the gap and child-execution policy reflected in them.

---

# 页面运行时：基础模型支持缺口与预览子流程限制

## 已确认的运行链路

- 公共页面 GET：`PublicPagesController#show` → `PageRendering` → `PageContentGenerator`。
- 会员页面 GET：`Member::PagesController#show` → 同一渲染器。生成的表单提交到统一的公共 UUID 端点。
- 提交：`PublicPagesController#submit` → `Pages::PublicSubmission` → `Pages::FormParams` → `ActivityTracer` → 生成的实体活动 → `EntityEntryContract` → 提交保存点内持久化。
- `new_model` 创建的是 `EntityEntry.build_for(bound_entity)`，不是 `extended_model` 指定的类。`build_contract` 声明实体属性，`save_model` 保存该契约。`EntityEntry` 没有指向基础记录的关联。
- 当前检查的生成器不使用旧的 `DetectAndRouteParams` / `PopulatePrimary` / `SaveAll` 辅助步骤。这些步骤现已在路由、赋值、持久化阶段拒绝基础模型输入。`SaveAll` 还会将契约保存返回 false 视为失败，并独立创建保存点，确保桥接记录保存失败时，即使存在外层事务也能回滚主记录写入。

## 基础模型支持缺口

`extended_model` 及获准模型的字段目录仅提供元数据，不授予运行时写入能力。当前链路没有基础记录解析器、模型专属可写字段契约，也没有基于认证凭据的基础记录归属策略。本次审计**不能证明构建器完整支持基础字段写入**。

运行时不渲染或接收基础模型字段。非空或结构错误的 `base[...]` 提交会在执行活动前被拒绝。即使提供与实体同名的属性、模型类名、记录 ID、`current_user_id`、`current_user_role` 或仿造的认证哈希，也不能启用基础模型写入。旧辅助步骤不会把基础字段混入实体 JSON，也不会对传入的基础模型调用 `assign_attributes`。赋值和持久化阶段还会拒绝 `EntityEntry` 之外的实际 ActiveRecord 目标，包括未提供基础模型参数时的基础模型契约目标。

后续适配器必须明确获准目标类型和可写字段，通过服务端控制的关联解析记录，从请求级 `FlowchartRuntime::Authentication` 凭据取得身份，校验租户范围及会员归属，并在提交事务内通过目标模型契约验证和保存。模型获准扩展不等于记录操作获授权。

## 未发布父流程的所有者预览

`ActivityTracer` 对直接流程执行和公共提交统一使用运行时执行包装器。调用方可以提供未发布的预览父流程；包装器保留该父流程已准备好的定义。子流程仍必须对当前租户可访问、已上线，并使用该租户的有效定义。父流程不会经过仅限已上线记录的查询。经 `ActivityClassBuilder` 进行的图表或结构检查不进入此执行包装器。

## 验证与文档交接

回归规格覆盖基础模型写入拒绝，以及未发布父流程调用合规子流程的情况。未运行测试。未修改构建器路由、控制器、编辑器、模板或编译产物写入行为。按要求未修改参考文档；对应的英文、简体中文运行时文档仍需同步支持缺口及子流程执行策略。
