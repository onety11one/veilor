# DNS: первый минимальный вариант

Реализованы чистый парсер DNS-адреса, типизированные модели и сборка DNS-фрагмента для явно заданного тестового плана: по одному серверу на роли resolver/outbound/direct/proxy. Это не замена полного `SingboxConfigBuilder.dns()` и не подключённый к UI код.

## Что изменилось относительно старой обвязки

В историческом генераторе использовались `address`, `addresses`, `address_resolver`, `address_strategy`, а DNS-метод возвращал объект напрямую. Текущий `lib/screens/my_profiles_screen.dart:1769` проверяет `dns.error` и получает `dns.data`. Текущий `lib/app/modules/server_manager.dart:1224` использует отсутствующие модели DomainResolver, ServerBatchOptions и TryParseList; запрос диагностики DNS теперь содержит servers/tag/domain/strategy.

В рамках этого пакета добавлен отдельный `DnsBuildResult<T>` с взаимоисключающими data/error. Он ещё не включён в текущий ReturnResult: мост следует делать при подключении генератора, не меняя общую модель ошибок приложения.

Типизированный формат сверялся с официальной документацией:

- [UDP](https://sing-box.sagernet.org/configuration/dns/server/udp/) — type/server/server_port и отличие поведения dialer от legacy.
- [TLS](https://sing-box.sagernet.org/configuration/dns/server/tls/) — тип и порт.
- [HTTPS](https://sing-box.sagernet.org/configuration/dns/server/https/) — путь и порт.
- [Dial fields](https://sing-box.sagernet.org/configuration/shared/dial/#domain_resolver) — domain_resolver.

Современный DNS dialer по умолчанию не повторяет старый выбор outbound. Поэтому proxy DNS получает **явный detour выбранного прокси**. После [проверки реального запуска](LIFECYCLE.md) прямые роли исправлены: они используют dialer без detour, поскольку обычное ядро отвергает detour на пустой direct outbound. Существующие detour-теги должны быть в полном конфиге; фрагмент сам их не создаёт и не подтверждает доступность сервера.

## Реализованный контракт

- UDP/TCP: порт 53, TLS: 853, HTTPS: 443; явный порт сохраняется.
- HTTPS без пути получает `/dns-query`; явно заданный путь сохраняется.
- IP-адреса IPv4/IPv6 и ASCII-имена DNS; IPv6 сериализуется без URI-скобок.
- Доменный DNS-сервер требует явный domain_resolver. Bootstrap в минимальном плане должен иметь literal IP: циклическое разрешение собственного имени не допускается.
- Стратегии соответствуют текущим IPStrategy: ipv4_only/prefer_ipv4/prefer_ipv6/ipv6_only.
- Ролевые теги, final=dns_proxy_out, independent_cache=true и cache_capacity=1024 сохранены по исторической модели. Пустой список правил здесь означает только отсутствие правил **в тестовом плане**.
- Неизвестный транспорт, неверный адрес/порт, учётные данные в URL, query/fragment, пустой tag или совпадающие direct/proxy tags дают типизированную ошибку. Ошибка одного сервера отменяет сборку целиком. Адреса и содержимое профилей в ошибку не попадают.

## Дополнительное локальное наблюдение

Из установленного Karing 1.2.25+2802 **только прочитаны имена полей и типы DNS-серверов** в service_core.json. Увидены серверы local/dhcp/udp/tls/hosts/predefined/batch/fakeip; domain_resolver содержит поля server/rewrite_ttl/strategy. Верхний DNS содержит final/servers/rules/strategy/independent_cache/cache_capacity.

Это подтверждает наличие собственного batch и дополнительных возможностей, но не их точную семантику. Значения адресов, правил, hosts, server tags и настройки пользователя в отчёт/фикстуры не копировались. Файл не изменялся; DNS-запросы, запуск/stop/reload VPN не выполнялись.

`rewrite_ttl`, ECS/client_subnet, статические hosts, local/DHCP, batch, FakeIP, QUIC/HTTP3, региональные/novice defaults и DNSQueryRequest пока не восстановлены. Поэтому текущие настройки Karing, где FakeIP включён по умолчанию и могут быть списки адресов, нельзя направлять в MinimalDnsBuilder. Он принимает только отдельный SingleServerDnsPlan без притворной поддержки этих настроек. Точное соответствие отсутствующему ядру 1.14.0 ещё не установлено.

## Проверка 21 октября 2026

Windows, Dart 3.12.2:

```powershell
dart run test/dns_test.dart
dart run test/projection_test.dart
dart analyze lib test
```

Итог: **23 DNS-теста + 14 тестов outbound**, анализатор — **No issues found**. Фикстура dns.expected.json задана отдельно и использует только тестовые адреса/имена. Проверены маршруты DNS, bootstrap, полная отмена при ошибке, порты, IPv6, несовместимые схемы, отсутствие утечки адреса в ошибку и независимость сериализации.

Это проверка структуры/логики, а не принятия конфига ядром или реального DNS-разрешения. Исторический DNS-код не использовался как JSON-эталон: его схема устарела. Архив и активные исходники приложения не менялись.

Следующий небольшой шаг: минимальный loopback mixed inbound и маршрутизация для того же VLESS-профиля, затем сборка целого тестового конфига. Отдельно проверить его подходящим ядром в режиме проверки конфигурации; не выдавать синтетический тест за восстановление всех режимов Karing.
