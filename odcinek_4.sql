-- =================================================================
-- TWORZENIE NOWEJ GRUPY (developers) ORAZ FUNKCJI PROJEKTOWYCH
-- =================================================================

-- Przełączenie na rolę administratora, aby zarządzać schematami, rolami i funkcjami.
SET ROLE admin_user;

-- Dodanie nowej roli biznesowej 'Developer' przy użyciu wcześniej zdefiniowanej funkcji pomocniczej.
SELECT add_role('Developer');

-- Stworzenie nowej roli aplikacyjnej (grupy) dla deweloperów.
CREATE ROLE developers;

-- Utworzenie dedykowanego schematu do przechowywania funkcji związanych z logiką projektów.
-- Dobra praktyka polegająca na oddzielaniu logiki aplikacyjnej od schematów z danymi (np. 'public').
CREATE SCHEMA project_functions;

-- Tworzy nową, bardziej zaawansowaną funkcję do dodawania projektów.
-- Funkcja ta od razu przypisuje projekt do wskazanego pracownika.
CREATE OR REPLACE FUNCTION project_functions.add_project(
    project_name VARCHAR(50),
    employee_email VARCHAR(100),
    start_date DATE,
    deadline_date DATE
)
    RETURNS VOID AS $$
DECLARE
    -- Deklaracja zmiennej do przechowania daty startowej.
    start_date_var DATE;
BEGIN
    -- Sprawdzenie, czy data startowa została podana. Jeśli nie (jest NULL), użyj bieżącej daty.
    -- Jest to przykład użycia instrukcji warunkowej IF w PL/pgSQL. Alternatywnie można by użyć funkcji COALESCE(start_date, CURRENT_DATE).
    IF start_date IS NULL THEN
        start_date_var := CURRENT_DATE;
    ELSE
        start_date_var := start_date;
    END IF;

    -- Użycie "łańcuchowego" CTE (Common Table Expression).
    -- Pierwsze CTE (`project`) wstawia nowy projekt i zwraca jego ID.
    -- Drugie CTE (`employee`) wyszukuje ID pracownika na podstawie jego adresu e-mail.
    -- Na końcu, główny INSERT używa danych z obu CTE, aby połączyć pracownika z projektem w tabeli 'employee_project'.
    WITH project AS (
        INSERT INTO public.projects (project_name, start_date, deadline_date) VALUES (project_name, start_date_var, deadline_date) RETURNING project_id
    ),
         employee AS
             (
                 SELECT employee_id FROM public.employees e WHERE e.email = employee_email
             )
    INSERT INTO public.employee_project (employee_id, project_id)  SELECT e.employee_id, p.project_id FROM employee e, project p;
END;
$$ LANGUAGE plpgsql;

-- Ponieważ funkcja `add_project` znajduje się w nowym schemacie, musimy nadać grupie 'manager_group' uprawnienia do jego używania.
GRANT USAGE ON SCHEMA project_functions TO manager_group;
-- Dodatkowo, menedżerowie muszą mieć uprawnienia do wykonywania samej funkcji.
GRANT EXECUTE ON FUNCTION project_functions.add_project(character varying, character varying, date, date) TO manager_group;

-- Zmiana roli na 'jsilver' (menedżer), aby przetestować dodawanie projektu nową funkcją.
SET ROLE jsilver;
SELECT project_functions.add_project('Testowy', 'jsilverhand@test.example', NULL, NULL);

-- =================================================================
-- DODAWANIE NOWYCH PRACOWNIKÓW DO GRUPY 'developers'
-- =================================================================

-- Przełączenie na użytkownika 'ljag' z grupy HR.
SET ROLE ljag;

-- Próba dodania nowego pracownika ('Geralt') z rolą 'Developer'.
-- To zapytanie się nie powiedzie!
SELECT add_employee('Geralt z Rivii', 'geralt@test.example', r.role_id, 20000, null, 'geralt', 'developers', 'haselko12') FROM public.business_roles r WHERE role_name = 'Developer';

-- Przełączenie na administratora, aby naprawić błąd.
-- Błąd wynikał z tego, że grupa 'hr_group' nie miała uprawnień do odczytu z tabeli 'public.business_roles',
-- co jest konieczne do znalezienia 'role_id' dla 'Developer'.
SET ROLE admin_user;
GRANT SELECT ON TABLE public.business_roles TO hr_group;

-- Powrót na rolę 'ljag'.
SET ROLE ljag;
-- I teraz dodamy sobie nowych niewolników, eee... pracowników, pracowników chciałem powiedzieć!
-- Po nadaniu uprawnień, operacja powinna się powieść.
SELECT add_employee('Geralt z Rivii', 'geralt@test.example', r.role_id, 20000, null, 'geralt', 'developers', 'haselko12') FROM public.business_roles r WHERE role_name = 'Developer';
SELECT add_employee('Link', 'link@test.example', r.role_id, 20000, null, 'link', 'developers', 'haselko12') FROM public.business_roles r WHERE role_name = 'Developer';
SELECT add_employee('Zelda', 'zelda@test.example', r.role_id, 20000, null, 'zelda', 'developers', 'haselko12') FROM public.business_roles r WHERE role_name = 'Developer';

-- =================================================================
-- PRZYPISYWANIE PROJEKTÓW I TWORZENIE POMOCNICZYCH WIDOKÓW
-- =================================================================

-- Wracamy na rolę administratora, żeby stworzyć kolejną funkcję pomocniczą.
SET ROLE admin_user;
-- Ta funkcja upraszcza proces przypisywania istniejącego projektu do istniejącego pracownika.
CREATE OR REPLACE FUNCTION project_functions.assign_project(
    project VARCHAR(50),
    employee_email VARCHAR(100)
)
    RETURNS VOID AS $$
BEGIN
    INSERT INTO public.employee_project (employee_id, project_id) SELECT e.employee_id, p.project_id FROM public.employees e, public.projects p WHERE e.email = employee_email AND p.project_name = project;
END;
$$ LANGUAGE plpgsql;

-- Użycie nowej funkcji. Nie zmieniamy już roli, wykonujemy to jako administrator.
SELECT project_functions.assign_project('Testowy', 'link@test.example');
SELECT project_functions.assign_project('Testowy', 'zelda@test.example');

-- Tworzymy widok 'auth', aby uprościć dostęp do ID pracownika i jego roli aplikacyjnej (loginu).
-- Będzie to bardzo przydatne w kontekście mechanizmu RLS (Row-Level Security).
CREATE VIEW public.auth AS
SELECT u.employee_id, r.app_role FROM app_security.users u JOIN app_security.app_roles r ON u.user_id = r.user_id;

-- Aby uniknąć wielokrotnego nadawania tych samych uprawnień, tworzymy nadrzędną rolę 'users'.
-- Będzie ona agregować podstawowe uprawnienia dla wszystkich grup.
CREATE ROLE users;
GRANT users TO manager_group;
GRANT users TO hr_group;
GRANT users TO admin_group;
GRANT users TO developers;

-- Wszyscy użytkownicy (poprzez dziedziczenie z roli 'users') będą mogli odczytywać dane z widoku 'auth'.
GRANT SELECT ON TABLE public.auth TO users;

-- Tworzymy funkcję pomocniczą `auth()`, która zwraca `employee_id` aktualnie zalogowanego użytkownika.
-- Funkcja odczytuje nazwę bieżącej roli z `current_user` i znajduje odpowiadające jej ID w naszym widoku.
CREATE OR REPLACE FUNCTION public.auth()
    RETURNS BIGINT AS $$
DECLARE employee_id BIGINT;
BEGIN
    SELECT a.employee_id INTO employee_id FROM public.auth a WHERE a.app_role = current_user;
    RETURN employee_id;
END;
$$ LANGUAGE plpgsql;


-- =================================================================
-- WPROWADZENIE DO BEZPIECZEŃSTWA NA POZIOMIE WIERSZA (ROW-LEVEL SECURITY)
-- =================================================================

-- Przechodzimy do sedna, czyli RLS. Najpierw włączamy mechanizm RLS dla tabeli 'projects'.
-- UWAGA: Domyślnie, po samym włączeniu, polityki RLS NIE dotyczą superużytkowników ani właściciela tabeli.
ALTER TABLE public.projects ENABLE ROW LEVEL SECURITY;

-- Zobaczmy, co się stanie, gdy użytkownik 'link' spróbuje odczytać projekty.
SET ROLE link;
-- Zapytanie nie zwróci żadnych wierszy! Dzieje się tak, ponieważ RLS jest włączony, ale nie ma jeszcze
-- żadnej polityki, która jawnie zezwalałaby na dostęp. Domyślnym zachowaniem jest blokowanie dostępu.
SELECT * FROM public.projects;

-- Wróćmy na administratora, aby to zweryfikować.
SET ROLE admin_user;
-- Najpierw nadajmy uprawnienia do odczytu na poziomie tabeli (to wciąż jest wymagane).
GRANT SELECT ON TABLE public.projects TO developers;

SET ROLE link;
-- Mimo posiadania uprawnień `SELECT`, użytkownik wciąż nic nie widzi z powodu braku polityki.
SELECT * FROM public.projects;

-- Aby udowodnić, że dane w tabeli istnieją, tymczasowo wyłączymy RLS.
SET ROLE admin_user;
ALTER TABLE public.projects DISABLE ROW LEVEL SECURITY;
SET ROLE link;
-- Teraz 'link' widzi wszystkie projekty.
SELECT * FROM public.projects;

-- Włączamy RLS ponownie i tworzymy naszą pierwszą politykę.
SET ROLE admin_user;
ALTER TABLE public.projects ENABLE ROW LEVEL SECURITY;

-- Polityka ta (`view_only_own_projects`) będzie dotyczyć operacji SELECT.
-- Warunek `USING` określa, które wiersze będą widoczne.
-- Wiersz będzie widoczny, jeśli `EXISTS` zwróci prawdę, czyli jeśli istnieje wpis w tabeli `employee_project`
-- łączący dany projekt (`projects.project_id`) z ID aktualnego użytkownika (zwracanym przez naszą funkcję `auth()`).
CREATE POLICY view_only_own_projects ON public.projects
    FOR SELECT
    USING (
    EXISTS (
        SELECT 1 FROM public.employee_project ep WHERE projects.project_id = ep.project_id AND ep.employee_id = auth()
    )
    );

-- Sprawdźmy to jako 'link'.
SET ROLE link;
-- Znowu błąd! Tym razem nasza polityka próbuje wykonać zapytanie do tabeli `employee_project`,
-- ale rola 'link' (poprzez 'developers') nie ma do niej uprawnień `SELECT`.
SELECT * FROM public.projects;

-- Naprawmy to, nadając brakujące uprawnienia.
SET ROLE admin_user;
GRANT SELECT ON TABLE public.employee_project TO developers;

-- Ostateczny test dla 'linka'.
SET ROLE link;
-- Sukces! Użytkownik 'link' widzi teraz tylko ten projekt, do którego jest przypisany.
SELECT * FROM public.projects;

-- A co zobaczy właściciel tabeli?
SET ROLE admin_user;
SELECT * FROM public.projects;
-- Właściciel wciąż widzi wszystkie projekty, ponieważ domyślnie polityki go nie dotyczą.

-- Aby polityki objęły również właściciela, musimy użyć polecenia FORCE.
ALTER TABLE public.projects FORCE ROW LEVEL SECURITY;
-- Teraz nawet admin_user podlega politykom.
SELECT * FROM public.projects;
-- Zapytanie nie zwraca wierszy, ponieważ 'admin_user' nie jest pracownikiem i funkcja auth() zwraca dla niego NULL.

-- =================================================================
-- ZARZĄDZANIE WIELOMA POLITYKAMI I ZMIENNE SESYJNE
-- =================================================================

/*
 Jak działają polityki, gdy jest ich kilka?
 PostgreSQL sprawdzi wszystkie polityki zdefiniowane dla danej tabeli i operacji.
 Jeśli CHOĆ JEDNA z nich zwróci TRUE dla danego wiersza, wiersz zostanie uwzględniony w wyniku.
 Polityki są łączone operatorem OR.

 Problem pojawia się, gdy jedna polityka da dostęp, a inna rzuci błędem (np. z braku uprawnień
 do tabeli użytej w warunku). W takim wypadku cała operacja zostanie przerwana.
*/
-- Usuńmy problematyczną politykę, żeby zacząć od nowa.
DROP POLICY IF EXISTS view_all_projects_for_admin ON public.projects;

-- Stworzymy teraz politykę, która używa zmiennej sesyjnej. Jest to ciekawa technika
-- do implementacji tymczasowego "trybu boga" lub specjalnego dostępu.
SET ROLE admin_user;
-- Ustawiamy niestandardową zmienną konfiguracyjną dla bieżącej sesji.
SET SESSION app.secret_access = '42';
-- Skrócony zapis: SET app.secret_access = '42';

-- Tworzymy politykę, która sprawdza wartość tej zmiennej.
CREATE POLICY view_projects_x_access ON public.projects
    FOR SELECT
    USING (
    current_setting('app.secret_access')::int = 42
    );

-- Zapytanie działa, bo zmienna jest ustawiona poprawnie.
SELECT * FROM public.projects;

-- Zresetujmy zmienną.
RESET app.secret_access;
-- Teraz zapytanie kończy się błędem, ponieważ `current_setting` zwraca NULL, gdy zmienna nie istnieje,
-- a próba rzutowania NULL na integer jest niedozwolona. Nasza polityka nie jest odporna na błędy.
SELECT * FROM public.projects;

-- Naprawmy to. Najpierw usuwamy starą politykę.
DROP POLICY view_projects_x_access ON public.projects;

-- Tworzymy nową, bezpieczniejszą wersję.
-- `current_setting('app.secret_access', true)` z drugim argumentem `true` zwróci NULL zamiast błędu, jeśli zmienna nie istnieje.
-- Sprawdzamy więc, czy zmienna w ogóle istnieje (IS NOT NULL) ORAZ czy ma poprawną wartość.
CREATE POLICY view_projects_x_access ON public.projects
    FOR SELECT
    USING (
    current_setting('app.secret_access', true) IS NOT NULL
        AND current_setting('app.secret_access', true)::int = 42
    );

-- Teraz zapytanie po prostu nie zwraca wierszy, ale nie powoduje błędu.
SELECT * FROM public.projects;

-- Użytkownik 'link' wciąż widzi swoje projekty, bo dla niego pierwsza polityka (`view_only_own_projects`) zwraca prawdę.
SET ROLE link;
SELECT * FROM public.projects;

-- Wróćmy na admina i ustawmy zmienną.
SET ROLE admin_user;
SET app.secret_access = '42';

-- Teraz polityka `view_projects_x_access` zwraca prawdę i administrator widzi wszystkie projekty.
SELECT * FROM public.projects;

-- =================================================================
-- POLITYKI DLA INSERT/UPDATE I ZAPOWIEDŹ KOLEJNYCH KROKÓW
-- =================================================================

-- Dodajmy jeszcze jedną politykę dla SELECT, opartą o logikę biznesową:
-- Użytkownicy powinni widzieć tylko aktywne projekty (te bez daty końcowej lub z datą w przyszłości).
CREATE POLICY view_only_current_projects ON public.projects
    FOR SELECT
    USING (
    projects.deadline_date IS NULL OR projects.deadline_date > NOW()
    );

-- Spróbujmy dodać nowy, zakończony już projekt jako menedżer.
SET ROLE jsilver;
SELECT project_functions.add_project('Zakończony', 'jsilverhand@test.example', NULL, (NOW() - INTERVAL '2 months')::date);

/*
 Dlaczego to zapytanie się NIE POWIODŁO?
 Polityki, które stworzyliśmy, dotyczą tylko operacji SELECT (klauzula USING).
 Nie zdefiniowaliśmy żadnych reguł dla INSERT, UPDATE czy DELETE.
 Domyślnie, jeśli istnieją polityki dla SELECT, ale nie ma ich dla INSERT, operacja wstawiania jest blokowana.

 Polityki dla operacji modyfikujących dane (INSERT, UPDATE) tworzy się za pomocą klauzuli WITH CHECK.
 Omówimy to w kolejnej części!
*/
-- Na potrzeby demonstracji, wyłączmy RLS, aby dodać archiwalny projekt.
SET ROLE admin_user;
ALTER TABLE public.projects DISABLE ROW LEVEL SECURITY;
SELECT project_functions.add_project('Zakończony', 'jsilverhand@test.example', NULL, (NOW() - INTERVAL '2 months')::date);
ALTER TABLE public.projects ENABLE ROW LEVEL SECURITY;


