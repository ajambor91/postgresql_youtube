-- =================================================================
-- POLITYKI RLS (INSERT, UPDATE, DELETE)
-- =================================================================
-- W tej części zajmiemy się politykami RLS dla operacji modyfikujących dane.
-- Naszym celem jest wprowadzenie reguł, które nie tylko kontrolują, KTO może
-- modyfikować dane, ale także JAKIE dane mogą być wstawiane lub aktualizowane.


-- =================================================================
-- STRUKTURA RÓL NADRZĘDNYCH
-- =================================================================
-- Zaczniemy od rozbudowy naszego systemu ról. Chcemy w łatwy sposób grupować
-- użytkowników (np. wszyscy z 'hr_group') w politykach RLS.
-- W tym celu tworzymy tabelę przechowującą nazwy naszych głównych grup/ról.

CREATE TABLE app_security.parent_roles (
                                           parent_role_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
                                           parent_role_name VARCHAR(50) NOT NULL UNIQUE
);

-- Od razu nadajemy wszystkim użytkownikom (poprzez rolę 'users') uprawnienia
-- do odczytu tej tabeli. Będzie to potrzebne w naszych przyszłych politykach.
GRANT SELECT ON TABLE app_security.parent_roles TO users;

-- Sprawdźmy, jakie mamy obecnie role w bazie danych.
\du

-- Wstawiamy nazwy naszych grup do nowej tabeli.
-- Możemy to zrobić w jednym zapytaniu, co jest bardziej wydajne.
INSERT INTO app_security.parent_roles (parent_role_name) VALUES ('developers'), ('hr_group'), ('manager_group'), ('admin_group');

-- Teraz musimy powiązać istniejące role aplikacyjne z ich rolami nadrzędnymi.
-- Dodajemy nową kolumnę i klucz obcy do tabeli 'app_roles'.
-- UWAGA: Celowo nie dodajemy od razu ograniczenia `NOT NULL`.
-- Zrobienie tego na tabeli, która już zawiera dane, spowodowałoby błąd.
-- Musimy najpierw uzupełnić dane we wszystkich istniejących wierszach.
ALTER TABLE app_security.app_roles
    ADD COLUMN parent_role BIGINT,
    ADD CONSTRAINT fk_parent_role FOREIGN KEY (parent_role) REFERENCES app_security.parent_roles(parent_role_id);


-- =================================================================
-- KROK 2: PRZYPISYWANIE RÓL NADRZĘDNYCH
-- =================================================================

-- Najpierw zobaczmy, które role nie mają jeszcze przypisanego rodzica.
SELECT r.app_role FROM app_security.app_roles r WHERE r.parent_role IS NULL;

-- Uzupełniamy brakujące dane. Używamy podzapytania do dynamicznego znalezienia
-- ID roli nadrzędnej na podstawie jej nazwy. To eleganckie i czytelne rozwiązanie.
UPDATE app_security.app_roles ar SET parent_role = (SELECT parent_role_id FROM app_security.parent_roles pr WHERE pr.parent_role_name = 'developers') WHERE ar.app_role = 'zelda';

-- Alternatywnie, to samo zadanie można wykonać przy użyciu CTE (Common Table Expression).
-- W tym konkretnym, prostym przypadku jest to nieco mniej optymalne, ponieważ tworzymy
-- tymczasowy zbiór danych, z którego potem odczytujemy. Jednak przy bardziej
-- złożonych operacjach, CTE potrafią znacznie poprawić czytelność kodu.
WITH parent AS (
    SELECT parent_role_id FROM app_security.parent_roles pr WHERE pr.parent_role_name = 'developers'
)
UPDATE app_security.app_roles ar SET parent_role = (SELECT parent.parent_role_id FROM parent) WHERE ar.app_role = 'link';

-- Aktualizujemy pozostałych pracowników.
UPDATE app_security.app_roles ar SET parent_role = (SELECT parent_role_id FROM app_security.parent_roles pr WHERE pr.parent_role_name = 'developers') WHERE ar.app_role = 'geralt';
UPDATE app_security.app_roles ar SET parent_role = (SELECT parent_role_id FROM app_security.parent_roles pr WHERE pr.parent_role_name = 'admin_group') WHERE ar.app_role = 'admin_user';
UPDATE app_security.app_roles ar SET parent_role = (SELECT parent_role_id FROM app_security.parent_roles pr WHERE pr.parent_role_name = 'hr_group') WHERE ar.app_role = 'ljag';
UPDATE app_security.app_roles ar SET parent_role = (SELECT parent_role_id FROM app_security.parent_roles pr WHERE pr.parent_role_name = 'manager_group') WHERE ar.app_role = 'jsilver';

-- Sprawdźmy raz jeszcze, czy wszystkie rekordy mają przypisanego rodzica.
SELECT r.app_role FROM app_security.app_roles r WHERE r.parent_role IS NULL;

-- Skoro wszystkie wiersze mają już wartość w kolumnie 'parent_role',
-- możemy bezpiecznie dodać ograniczenie NOT NULL.
ALTER TABLE app_security.app_roles ALTER COLUMN parent_role SET NOT NULL;


-- =================================================================
-- POLITYKA INSERT Z KLAUZULĄ "WITH CHECK"
-- =================================================================
-- Czas na naszą pierwszą politykę dla operacji INSERT.
-- Chcemy, aby projekty mogli dodawać TYLKO użytkownicy z grupy 'manager_group'.
-- Użyjemy do tego klauzuli `WITH CHECK`, która weryfikuje warunek PRZED zapisaniem wiersza.
CREATE POLICY add_project_only_by_manager ON public.projects
    FOR INSERT
    WITH CHECK (
    -- Warunek sprawdza, czy aktualnie zalogowany użytkownik (public.auth())
    -- jest powiązany z rolą nadrzędną o nazwie 'manager_group'.
    EXISTS (
        SELECT 1
        FROM app_security.app_roles a
                 INNER JOIN app_security.parent_roles p ON p.parent_role_id = a.parent_role
                 INNER JOIN app_security.users u ON u.user_id = a.user_id
        WHERE u.employee_id = public.auth() AND p.parent_role_name = 'manager_group'
    )
    );

-- Spróbujmy dodać projekt jako 'admin_user'.
-- Pamiętajmy z poprzedniego odcinka, że na tabeli 'projects' włączyliśmy `FORCE ROW LEVEL SECURITY`.
SELECT project_functions.add_project('Projekt admina', 'jsilverhand@test.example', NULL, NULL);
-- Zapytanie kończy się błędem! Mimo że 'admin_user' jest właścicielem tabeli,
-- polityka `FORCE` obowiązuje również jego, a warunek `WITH CHECK` nie został spełniony.

-- A teraz spróbujmy jako menedżer 'jsilver'.
SET ROLE jsilver;
SELECT project_functions.add_project('Johnny', 'jsilverhand@test.example', NULL, NULL);
-- Sukces! Użytkownik należy do grupy 'manager_group', więc polityka zezwoliła na INSERT.


-- =================================================================
-- "WITH CHECK" DO WALIDACJI DANYCH
-- =================================================================
-- Klauzula `WITH CHECK` służy nie tylko do autoryzacji, ale przede wszystkim
-- do sprawdzania, czy DANE, które próbujemy wstawić, są zgodne z regułami.

-- Przykład 1: Blokowanie dodawania konkretnej roli biznesowej.
SET ROLE admin_user;
ALTER TABLE public.business_roles ENABLE ROW LEVEL SECURITY;

-- Tworzymy politykę, która blokuje możliwość dodania roli o nazwie 'Dyrektor'.
CREATE POLICY cannot_add_director_role ON public.business_roles
    FOR INSERT
    WITH CHECK (
    role_name <> 'Dyrektor'
    );

-- Próba dodania roli 'Dyrektor' jako admin_user.
INSERT INTO business_roles (role_name)  VALUES ('Dyrektor');
-- Działa! Dlaczego? Ponieważ nie włączyliśmy `FORCE ROW LEVEL SECURITY`,
-- więc polityka nie dotyczy właściciela tabeli ('admin_user').
DELETE FROM business_roles WHERE role_name = 'Dyrektor';

-- Włączmy `FORCE` i spróbujmy ponownie.
ALTER TABLE public.business_roles FORCE ROW LEVEL SECURITY;
INSERT INTO business_roles (role_name)  VALUES ('Dyrektor');
-- Teraz operacja jest blokowana. Polityka działa zgodnie z oczekiwaniami.

-- A co z inną rolą?
INSERT INTO business_roles (role_name)  VALUES ('Dyrektorka');
-- Działa. Polityka blokuje tylko dokładną nazwę 'Dyrektor'.

-- Przykład 2: Łączenie walidacji danych i autoryzacji.
-- Chcemy, aby nowe departamenty mogła dodawać tylko grupa HR,
-- i dodatkowo, aby nie można było dodać departamentu o nazwie 'Dyrekcja'.
ALTER TABLE public.departments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.departments FORCE ROW LEVEL SECURITY;

CREATE POLICY add_department_by_hr_and_no_directors ON public.departments
    FOR INSERT
    WITH CHECK (
    -- Warunek 1: Walidacja danych (nazwa nie może być 'Dyrekcja')
    department_name <> 'Dyrekcja' AND
        -- Warunek 2: Autoryzacja (użytkownik musi być w 'hr_group')
    EXISTS (
        SELECT 1
        FROM app_security.app_roles a
                 INNER JOIN app_security.parent_roles p ON p.parent_role_id = a.parent_role
                 INNER JOIN app_security.users u ON u.user_id = a.user_id
        WHERE u.employee_id = public.auth() AND p.parent_role_name = 'hr_group'
    )
    );

-- Nadajemy grupie HR uprawnienia do modyfikacji tabeli.
GRANT UPDATE, INSERT ON departments TO hr_group;

-- Próba dodania departamentu jako admin (nie jest w HR).
INSERT INTO public.departments (department_name) VALUES ('dyr');
-- Błąd, polityka blokuje z powodu braku przynależności do 'hr_group'.

-- Przełączamy się na użytkownika z HR.
SET ROLE ljag;
INSERT INTO public.departments (department_name) VALUES ('dyr');
-- Znowu błąd! Tym razem to klasyczny problem z uprawnieniami.
-- Nasza polityka musi mieć dostęp do tabel w schemacie `app_security`.

-- Wracamy na admina i nadajemy brakujące uprawnienia.
SET ROLE admin_user;
GRANT SELECT ON app_security.app_roles TO users;
GRANT SELECT ON app_security.parent_roles TO users;
GRANT SELECT ON app_security.users TO users;

-- Wracamy na użytkownika HR i próbujemy ponownie.
SET ROLE ljag;
INSERT INTO public.departments (department_name) VALUES ('dyr');
-- Sukces!

-- A teraz spróbujmy dodać zablokowany departament.
INSERT INTO public.departments (department_name) VALUES ('Dyrekcja');
-- Błąd! Tym razem zadziałał warunek walidacji danych (`department_name <> 'Dyrekcja'`).

-- Ciekawostka: Autoryzację można też zdefiniować bezpośrednio w polityce.
-- To upraszcza warunek `WITH CHECK`.
SET ROLE admin_user;
DROP POLICY add_department_by_hr_and_no_directors ON public.departments;
DELETE FROM public.departments WHERE department_name LIKE 'Dyr%' OR department_name LIKE 'dyr%';

-- Polityka dotyczy tylko operacji INSERT wykonywanych przez członków 'hr_group'.
CREATE POLICY add_department_by_hr_and_no_directors ON public.departments
    FOR INSERT TO hr_group -- <--- Kluczowa zmiana!
    WITH CHECK (
    department_name <> 'Dyrekcja'
    );

-- Jako admin (nie w hr_group) nie możemy nic dodać, bo nie ma dla nas polityki zezwalającej.
-- INSERT INTO public.departments (department_name) VALUES ('dyr'); -- To by zwróciło błąd

-- Jako użytkownik z HR możemy dodawać, o ile dane są poprawne.
SET ROLE ljag;
INSERT INTO public.departments (department_name) VALUES ('dyr'); -- OK
-- INSERT INTO public.departments (department_name) VALUES ('Dyrekcja'); -- Błąd


-- =================================================================
-- KOMPLEKSOWY SCENARIUSZ - TABELA CZASU PRACY
-- =================================================================
SET ROLE admin_user;

-- Tworzymy tabelę do logowania czasu pracy.
CREATE TABLE public.work_times (
                                   work_time_id BIGINT GENERATED ALWAYS AS IDENTITY,
                                   hours BIGINT NOT NULL ,
    -- Domyślnie przypisujemy wpis do aktualnie zalogowanego użytkownika.
                                   employee_id BIGINT NOT NULL DEFAULT auth(),
                                   month BIGINT NOT NULL,
                                   CONSTRAINT fk_employee FOREIGN KEY (employee_id) REFERENCES public.employees (employee_id)
);

-- Nadajemy podstawowe uprawnienia.
GRANT SELECT, INSERT, UPDATE ON public.work_times TO users;

-- Tworzymy unikalny indeks złożony z dwóch kolumn.
-- Zapewni on na poziomie bazy danych, że jeden pracownik
-- może mieć tylko jeden wpis dla danego miesiąca.
CREATE UNIQUE INDEX uidx_work_times ON public.work_times (month, employee_id);

-- Włączamy RLS i od razu wersję `FORCE`, aby objąć nią wszystkich, w tym właściciela.
ALTER TABLE public.work_times ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.work_times FORCE ROW LEVEL SECURITY;

-- Polityka dla INSERT - czysta walidacja danych.
CREATE POLICY insert_only_valid_hours ON public.work_times
    FOR INSERT
    WITH CHECK (
    month >= 1 AND month <= 12 AND
    hours >= 8
    );

-- Testy polityki INSERT:
-- Nieprawidłowy miesiąc (0) i za mało godzin (1) -> BŁĄD
-- INSERT INTO public.work_times (hours, month) VALUES (1,0);

-- Prawidłowy miesiąc (1), ale za mało godzin (1) -> BŁĄD
-- INSERT INTO public.work_times (hours, month) VALUES (1,1);

-- Wszystkie dane poprawne -> SUKCES
INSERT INTO public.work_times (hours, month) VALUES (8,1);

-- Próba dodania drugiego wpisu dla tego samego miesiąca -> BŁĄD
-- Tym razem blokuje nas unikalny indeks, a nie polityka RLS.
-- INSERT INTO public.work_times (hours, month) VALUES (8,1);

-- Sprawdźmy, co jest w tabeli.
SELECT * FROM public.work_times;
-- Nic nie widać! Dlaczego? Bo nie mamy polityki dla operacji SELECT!

-- Dodajmy politykę, która pozwala każdemu widzieć TYLKO WŁASNE wpisy.
CREATE POLICY select_only_own_hours ON public.work_times
    FOR SELECT
    USING (
    employee_id = auth()
    );

-- Sprawdźmy ponownie.
SELECT * FROM public.work_times;
-- Teraz widzimy swój wiersz.

-- Na koniec, polityka dla UPDATE.
CREATE POLICY update_only_own_hours ON public.work_times
    FOR UPDATE
    -- Klauzula USING określa, które wiersze użytkownik MOŻE w ogóle modyfikować.
    -- W tym przypadku: tylko własne.
    USING (
    employee_id = auth()
    )
    -- Klauzula WITH CHECK sprawdza, czy NOWE dane są poprawne.
    -- Chcemy, aby łączna liczba godzin nie przekroczyła 260.
    WITH CHECK (
    hours <= 260
    );

-- Spróbujmy zaktualizować godziny.
UPDATE public.work_times SET hours = (SELECT hours + 5 FROM public.work_times WHERE employee_id = auth()) WHERE employee_id = auth() AND month = 1;
SELECT * FROM public.work_times;
-- Działa, godziny zostały zaktualizowane.

-- A teraz spróbujmy przekroczyć limit 260 godzin.
UPDATE public.work_times SET hours = (SELECT hours + 259 FROM public.work_times WHERE employee_id = auth()) WHERE employee_id = auth() AND month = 1;
-- Błąd, polityka `WITH CHECK` zablokowała operację.

-- Sprawdźmy, czy inny użytkownik widzi nasze dane.
SET ROLE jsilver;
INSERT INTO public.work_times (hours, month) VALUES (9,1);
SELECT * FROM public.work_times;
-- 'jsilver' widzi tylko swój wpis z 9 godzinami. Perfekcyjnie.

-- Próba aktualizacji danych innego użytkownika.
-- Najpierw znajdźmy ID admina.
-- SELECT u.employee_id, a.app_role FROM app_security.users u INNER JOIN app_security.app_roles a ON a.user_id = u.user_id; -- (admin_user ma id 1)
UPDATE public.work_times SET hours = 10 WHERE employee_id = 1 AND month = 1;
-- "0 rows updated". Klauzula `USING` z polityki UPDATE sprawiła, że wiersz
-- należący do 'admin_user' był dla 'jsilver' niewidoczny, więc nie mógł go zaktualizować.

-- =================================================================
-- ATYBUT BYPASSRLS - TYLNE WEJŚCIE DLA ADMINA
-- =================================================================
-- Czasem administrator musi mieć możliwość obejścia wszystkich polityk RLS,
-- np. w celach diagnostycznych lub naprawczych. Służy do tego atrybut BYPASSRLS.
SET ROLE admin_user;
SELECT * FROM public.work_times;
-- Admin widzi tylko swoje wiersze, bo podlega polityce `FORCE`.

-- Przełączamy się na superużytkownika, aby nadać atrybut.
SET ROLE postgres;
ALTER ROLE admin_user BYPASSRLS;

-- Wracamy na admina.
SET ROLE admin_user;
SELECT * FROM public.work_times;
-- Teraz admin widzi wszystkie wiersze w tabeli, ignorując polityki RLS.
-- To bardzo potężne narzędzie, którego należy używać z rozwagą!

-- PS. Część walidacji (np. `hours >= 8`) można by też zaimplementować
-- za pomocą ograniczenia `CONSTRAINT CHECK` na poziomie tabeli, ale to temat na inny odcinek!

