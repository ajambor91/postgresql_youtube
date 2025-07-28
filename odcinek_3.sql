
-- =================================================================
-- ZAPYTANIA DO METADANYCH (INFORMATION_SCHEMA)
-- =================================================================

-- Wyświetla wszystkie tabele, do których bieżący użytkownik ma dostęp, ze wszystkich schematów.
SELECT * FROM information_schema.tables;

-- Wyświetla tabele tylko z schematów użytkownika (pomija systemowe schematy 'pg_%' i 'information_schema').
SELECT * FROM information_schema.tables WHERE table_schema IN (SELECT schema_name FROM information_schema.schemata WHERE schema_name NOT LIKE 'pg_%' AND schema_name <> 'information_schema');

-- Wyświetla informacje o wszystkich ograniczeniach (constraints) w tabelach, łącząc dwie tabele metadanych.
SELECT * FROM information_schema.table_constraints tc JOIN information_schema.key_column_usage kc ON tc.constraint_name = tc.constraint_name;
/*
 Wyjaśnienie kolumn:
 table_catalog                  - Nazwa bazy danych, w której znajduje się tabela.
 table_schema                   - Nazwa schematu, w którym znajduje się tabela (np. 'public', 'auditing').
 table_name                     - Nazwa tabeli.
 table_type                     - Typ obiektu. 'BASE TABLE' oznacza zwykłą tabelę, może też być np. 'VIEW' dla widoku.
 self_referencing_column_name   - Nazwa kolumny w relacji rekurencyjnej (gdy tabela odwołuje się do samej siebie). Zazwyczaj NULL.
 reference_generation           - Sposób generowania wartości w kolumnie referencyjnej. Zazwyczaj NULL.
 user_defined_type_catalog,
 user_defined_type_schema,
 user_defined_type_name         - Informacje o typie danych zdefiniowanym przez użytkownika, jeśli tabela jest "typed table". Dla zwykłych tabel wartości te to NULL.
 is_insertable_into             - Określa, czy można wstawiać dane do tabeli ('YES'/'NO'). Dla widoków może być 'NO'.
 is_typed                       - Wskazuje, czy tabela jest "typed table" ('YES'/'NO'), czyli oparta na złożonym typie danych.
 commit_action                  - Akcja wykonywana na tabeli tymczasowej po zatwierdzeniu transakcji (COMMIT). Dla tabel stałych jest to NULL.
*/
-- Wyświetla tylko ograniczenia typu KLUCZ OBCY (FOREIGN KEY) z schematów użytkownika.
SELECT * FROM information_schema.table_constraints tc JOIN information_schema.key_column_usage kc ON tc.constraint_name = tc.constraint_name WHERE tc.table_schema NOT LIKE 'pg_%' AND tc.table_schema <> 'information_schema' AND tc.constraint_type = 'FOREIGN KEY';

-- =================================================================
-- ROZSZERZENIE RELACJI I UPRAWNIEŃ
-- =================================================================

-- Dodaje klucz obcy do tabeli 'attendances', łącząc ją z tabelą 'employees'.
-- Ponieważ kolumna w obu tabelach nazywa się tak samo ('employee_id'), nie musimy jej jawnie wymieniać w części REFERENCES.
-- PostgreSQL domyślnie użyje kolumny klucza podstawowego z tabeli 'employees'.
ALTER TABLE public.attendances ADD CONSTRAINT fk_employee FOREIGN KEY (employee_id) REFERENCES public.employees;

-- Dodaje dwa klucze obce do tabeli łączącej 'employee_project'.
ALTER TABLE public.employee_project
    -- Dodaje klucz obcy dla 'project_id'.
    -- Tutaj jawnie wskazujemy, że kolumna 'project_id' w tabeli 'employee_project'
    -- odnosi się do kolumny 'project_id' w tabeli 'projects'. Jest to dobra praktyka dla czytelności.
    ADD CONSTRAINT fk_project FOREIGN KEY (project_id) REFERENCES public.projects(project_id),
    -- Dodaje klucz obcy dla 'employee_id', podobnie jak w przykładzie powyżej.
    ADD CONSTRAINT fk_employee FOREIGN KEY (employee_id) REFERENCES public.employees;

-- =================================================================
-- TWORZENIE WYZWALACZY I FUNKCJI POMOCNICZYCH
-- =================================================================

-- Tworzy wyzwalacz, który będzie logował każdą operację wstawienia (INSERT) do tabeli 'projects'.
CREATE OR REPLACE TRIGGER log_insert_proj
    AFTER INSERT ON public.projects
    FOR EACH ROW
EXECUTE FUNCTION log_event('INSERT');

-- Tworzy wyzwalacz, który będzie logował każdą operację aktualizacji (UPDATE) w tabeli 'projects'.
CREATE OR REPLACE TRIGGER log_update_proj
    AFTER UPDATE ON public.projects
    FOR EACH ROW
EXECUTE FUNCTION log_event('UPDATE');

-- Tworzy funkcję pomocniczą 'add_role' do łatwiejszego dodawania nowych ról biznesowych.
-- SECURITY DEFINER sprawia, że funkcja wykonuje się z uprawnieniami jej właściciela, a nie użytkownika, który ją wywołuje.
CREATE OR REPLACE FUNCTION add_role(role_name VARCHAR(50))
    RETURNS VOID AS $$
BEGIN
    INSERT INTO public.business_roles (role_name) VALUES (role_name);
END
$$ LANGUAGE plpgsql SECURITY DEFINER ;

-- =================================================================
-- ZARZĄDZANIE NOWĄ GRUPĄ RÓL (manager_group)
-- =================================================================

-- Tworzy nową grupę ról o nazwie 'manager_group'.
CREATE ROLE manager_group;

-- Używa wcześniej zdefiniowanej funkcji, aby dodać rolę 'Manager' do tabeli ról biznesowych.
SELECT add_role('Manager');

-- Dodaje nowego pracownika ('Johnny Silverhand') i jednocześnie tworzy dla niego rolę do logowania ('jsilver'),
-- przypisując ją do grupy 'manager_group'.
SELECT add_employee('Johnny Silverhand', 'jsilverhand@test.example', r.role_id, 20000, null, 'jsilver', 'manager_group', 'haselko12') FROM public.business_roles r WHERE role_name = 'Manager';

-- Przełącza kontekst sesji na nowo utworzonego użytkownika 'jsilver', aby przetestować jego uprawnienia.
SET ROLE jsilver;

-- Próba dodania projektu i przypisania go do siebie. To zapytanie się nie powiedzie,
-- ponieważ rola 'jsilver' (poprzez 'manager_group') nie ma jeszcze żadnych uprawnień do tabel 'projects' i 'employees'.
WITH new_project_id AS (INSERT INTO public.projects (project_name, start_date) VALUES ('Mikoshi Fucked Up', NOW()) RETURNING project_id) INSERT INTO public.employee_project (employee_id, project_id) SELECT e.employee_id, n.project_id FROM public.employees e, new_project_id n WHERE e.email = 'jsilverhand@test.example';

-- Przełącza się na superużytkownika, aby nadać uprawnienia.
SET ROLE postgres;

-- Nadaje grupie 'manager_group' pełne uprawnienia (SELECT, INSERT, UPDATE, DELETE) do tabeli 'projects'.
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.projects TO manager_group;
-- Nadaje grupie 'manager_group' pełne uprawnienia do tabeli 'employee_project'.
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.employee_project TO manager_group;

-- Ponownie przełącza się na 'jsilver', aby sprawdzić, czy uprawnienia działają.
SET ROLE jsilver;

-- Ponowna próba dodania projektu. Ta próba również się nie powiedzie, ponieważ rola 'jsilver' wciąż nie ma
-- uprawnień do odczytu (SELECT) z tabeli 'employees', co jest wymagane w podzapytaniu.
WITH new_project_id AS (INSERT INTO public.projects (project_name, start_date) VALUES ('Mikoshi Fucked Up', NOW()) RETURNING project_id) INSERT INTO public.employee_project (employee_id, project_id) SELECT e.employee_id, n.project_id FROM public.employees e, new_project_id n WHERE e.email = 'jsilverhand@test.example';

-- Znowu przełączenie na superużytkownika w celu nadania brakujących uprawnień.
SET ROLE postgres;

-- Nadaje grupie 'manager_group' uprawnienie do odczytu (SELECT) z tabeli 'employees'.
GRANT SELECT ON TABLE public.employees TO manager_group;

-- Przełączenie na 'jsilver'.
SET ROLE jsilver;

-- Kolejna próba. Tym razem zapytanie się nie powiedzie, ponieważ funkcja logująca zdarzenia ('log_event')
-- próbuje zapisać dane w schemacie 'auditing', do którego 'jsilver' nie ma dostępu.
WITH new_project_id AS (INSERT INTO public.projects (project_name, start_date) VALUES ('Mikoshi Fucked Up', NOW()) RETURNING project_id) INSERT INTO public.employee_project (employee_id, project_id) SELECT e.employee_id, n.project_id FROM public.employees e, new_project_id n WHERE e.email = 'jsilverhand@test.example';

-- Przełączenie na rolę 'admin_user', która jest właścicielem schematów.
SET ROLE admin_user;

-- Nadaje uprawnienie do używania (ale nie modyfikowania struktury) schematów 'auditing' i 'app_security' grupie 'manager_group'.
GRANT USAGE ON SCHEMA auditing TO manager_group;
GRANT USAGE ON SCHEMA app_security TO manager_group;

-- Ponowne sprawdzenie jako 'jsilver'.
SET ROLE jsilver;

-- I kolejna nieudana próba. Tym razem błąd wynika z braku uprawnień do odczytu tabeli 'app_roles',
-- co jest potrzebne funkcji 'log_event' do znalezienia user_id.
WITH new_project_id AS (INSERT INTO public.projects (project_name, start_date) VALUES ('Mikoshi Fucked Up', NOW()) RETURNING project_id) INSERT INTO public.employee_project (employee_id, project_id) SELECT e.employee_id, n.project_id FROM public.employees e, new_project_id n WHERE e.email = 'jsilverhand@test.example';

-- Przełączenie na 'admin_user' w celu nadania ostatnich potrzebnych uprawnień.
SET ROLE admin_user;
GRANT SELECT ON TABLE app_security.app_roles TO manager_group;
GRANT INSERT ON TABLE auditing.logs TO manager_group;
GRANT SELECT ON TABLE app_security.users TO manager_group;

-- Ostateczne przełączenie na 'jsilver'.
SET ROLE jsilver;

-- TA PRÓBA POWINNA SIĘ UDAĆ! Użytkownik 'jsilver' ma teraz wszystkie wymagane uprawnienia.
WITH new_project_id AS (INSERT INTO public.projects (project_name, start_date) VALUES ('Mikoshi Fucked Up', NOW()) RETURNING project_id) INSERT INTO public.employee_project (employee_id, project_id) SELECT e.employee_id, n.project_id FROM public.employees e, new_project_id n WHERE e.email = 'jsilverhand@test.example';

-- Sprawdzenie, czy dane zostały poprawnie wstawione.
SELECT * FROM public.projects;
SELECT * FROM public.employee_project;
SELECT * FROM app_security.users;
SELECT * FROM app_security.app_roles;

-- =================================================================
-- TESTOWANIE UPRAWNIEŃ GRUPY HR (hr_group)
-- =================================================================

-- Przełączenie na użytkownika 'ljag' z grupy 'hr_group'.
SET ROLE ljag;
-- Próba odczytu tabeli pracowników. Nie powiedzie się, bo grupa 'hr_group' nie ma jeszcze uprawnień.
SELECT * FROM public.employees;

-- Przełączenie na administratora, aby nadać uprawnienia.
SET ROLE admin_user;
-- Nadanie pełnych uprawnień do tabeli 'employees' dla grupy 'hr_group'.
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.employees TO hr_group;

-- Ponowne przełączenie na 'ljag'.
SET ROLE ljag;
-- Teraz odczyt powinien się powieść.
SELECT * FROM public.employees;

-- Powrót do administratora.
SET ROLE admin_user;

-- =================================================================
-- TWORZENIE I UŻYWANIE WIDOKÓW (VIEWS)
-- =================================================================

-- Zapytanie łączące pracowników z projektami, aby wyświetlić ich nazwy.
SELECT e.employee_id, e.full_name, e.email, pr.project_name FROM public.employees e JOIN public.employee_project ep ON e.employee_id = ep.employee_id JOIN public.projects pr ON ep.project_id = pr.project_id;

-- Tworzy widok 'employees_with_projects_name' na podstawie powyższego zapytania.
-- Widok działa jak wirtualna tabela, upraszczając skomplikowane zapytania.
CREATE VIEW public.employees_with_projects_name AS
SELECT e.employee_id, e.full_name, e.email, pr.project_name FROM public.employees e JOIN public.employee_project ep ON e.employee_id = ep.employee_id JOIN public.projects pr ON ep.project_id = pr.project_id;

-- Odpytanie nowo utworzonego widoku.
SELECT * FROM public.employees_with_projects_name;

-- Przełączenie na 'ljag', aby sprawdzić dostęp do widoku.
SET ROLE ljag;
-- Próba nieudana - brak uprawnień do widoku.
SELECT * FROM public.employees_with_projects_name;

-- Nadanie uprawnień do widoku.
SET ROLE admin_user;
GRANT SELECT ON TABLE public.employees_with_projects_name TO hr_group;

-- Ponowna próba jako 'ljag'.
SET ROLE ljag;
-- Teraz odczyt widoku działa.
SELECT * FROM public.employees_with_projects_name;
-- Można też wybierać konkretne kolumny z widoku.
SELECT full_name FROM public.employees_with_projects_name;

-- Powrót do administratora.
SET ROLE admin_user;

-- Bardziej złożone zapytanie, które łączy dane pracownika, jego rolę biznesową, dział i login.
SELECT ep.full_name, ep.email, b.role_name AS business_role, de.department_name, ar.app_role AS login FROM public.employees ep
                                                                                                               LEFT JOIN public.departments de ON de.department_id = ep.department_id
                                                                                                               LEFT JOIN public.business_roles b on ep.role_id = b.role_id JOIN app_security.users u ON u.employee_id = ep.employee_id
                                                                                                               JOIN app_security.app_roles ar ON ar.user_id = u.user_id;

-- Tworzy drugi, bardziej kompleksowy widok.
CREATE VIEW public.employees_with_users AS
SELECT ep.full_name, ep.email, b.role_name AS business_role, de.department_name, ar.app_role AS login FROM public.employees ep
                                                                                                               LEFT JOIN public.departments de ON de.department_id = ep.department_id
                                                                                                               LEFT JOIN public.business_roles b on ep.role_id = b.role_id JOIN app_security.users u ON u.employee_id = ep.employee_id
                                                                                                               JOIN app_security.app_roles ar ON ar.user_id = u.user_id;

-- Nadaje uprawnienia do nowego widoku dla grupy HR.
GRANT SELECT ON TABLE public.employees_with_users TO hr_group;

-- Testowanie dostępu do nowego widoku jako 'ljag'.
SET ROLE ljag;
SELECT * FROM public.employees_with_users;
-- Filtrowanie danych z widoku.
SELECT * FROM public.employees_with_users WHERE business_role = 'Administrator';
-- Łączenie widoku z inną tabelą.
SELECT * FROM public.employees e JOIN public.employees_with_users eu ON e.email = eu.email;

-- Powrót do superużytkownika.
SET ROLE postgres;

-- Ponowne wyświetlenie wszystkich tabel z schematów użytkownika.
SELECT * FROM information_schema.tables t WHERE t.table_schema NOT LIKE 'pg_%' AND t.table_schema <> 'information_schema';
