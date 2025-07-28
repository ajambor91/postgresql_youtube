-- =================================================================
-- KONFIGURACJA RÓL I UPRAWNIEŃ
-- =================================================================

-- Tworzy nową grupę ról o nazwie 'admin_group'. Grupy ułatwiają zarządzanie uprawnieniami.
CREATE ROLE admin_group;

-- Nadaje wszystkie uprawnienia (np. tworzenie tabel, wstawianie danych) do bazy danych 'bitstechworld' dla grupy 'admin_group'.
GRANT ALL PRIVILEGES ON DATABASE bitstechworld TO admin_group;

-- Ustawia grupę 'admin_group' jako właściciela schematu 'public'.
-- Oznacza to, że członkowie tej grupy mają pełną kontrolę nad tym schematem.
ALTER SCHEMA public OWNER TO admin_group;

-- Tworzy nowego użytkownika (rolę) o nazwie 'admin_user' z hasłem 'examplePassword'.
-- Słowo kluczowe 'LOGIN' pozwala temu użytkownikowi na logowanie się do bazy danych.
CREATE ROLE admin_user WITH LOGIN PASSWORD 'examplePassword';

-- Przypisuje użytkownika 'admin_user' do grupy 'admin_group', dzięki czemu dziedziczy on wszystkie uprawnienia tej grupy.
GRANT admin_group TO admin_user;

-- Przełącza bieżącą sesję, aby działała jako użytkownik 'admin_user'.
-- Wszystkie kolejne polecenia będą wykonywane z uprawnieniami tego użytkownika.
SET ROLE admin_user;

-- =================================================================
-- SEKCJA 2: TWORZENIE SCHEMATÓW I TABEL
-- =================================================================

-- Tworzy nowy schemat o nazwie 'app_security' do przechowywania tabel związanych z bezpieczeństwem aplikacji.
CREATE SCHEMA app_security;

-- Tworzy tabelę 'users' w schemacie 'app_security' do przechowywania informacji o użytkownikach aplikacji.
CREATE TABLE app_security.users (
                                    user_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, -- Unikalny identyfikator użytkownika, generowany automatycznie.
                                    employee_id BIGINT UNIQUE NOT NULL, -- ID pracownika, musi być unikalne i nie może być puste.
                                    created_at TIMESTAMPTZ NOT NULL,   -- Data i czas utworzenia rekordu (z uwzględnieniem strefy czasowej).
                                    updated_at TIMESTAMPTZ NOT NULL    -- Data i czas ostatniej aktualizacji rekordu.
);

-- Tworzy tabelę 'app_roles' do przypisywania ról aplikacyjnych do użytkowników.
CREATE TABLE app_security.app_roles (
                                        app_role_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, -- Unikalny identyfikator przypisania roli.
                                        user_id BIGINT NOT NULL,          -- ID użytkownika, do którego przypisana jest rola.
                                        app_role TEXT NOT NULL            -- Nazwa roli aplikacyjnej (np. 'admin', 'user').
);

-- Tworzy nowy schemat o nazwie 'auditing' do przechowywania logów i danych audytowych.
CREATE SCHEMA auditing;

-- Tworzy tabelę 'logs' do zapisywania zdarzeń w systemie (np. kto i kiedy zmodyfikował dane).
CREATE TABLE auditing.logs (
                               log_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, -- Unikalny identyfikator logu.
                               user_id BIGINT NOT NULL,          -- ID użytkownika, który wywołał zdarzenie.
                               event TEXT,                       -- Opis zdarzenia (np. 'INSERT', 'UPDATE').
                               date TIMESTAMPTZ NOT NULL,        -- Data i czas zdarzenia.
                               details JSONB NOT NULL            -- Szczegółowe informacje o zdarzeniu w formacie JSONB.
);

-- Tworzy tabelę 'employees' w domyślnym schemacie 'public' do przechowywania danych o pracownikach.
CREATE TABLE public.employees (
                                  employee_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, -- Unikalny ID pracownika.
                                  full_name VARCHAR(100) NOT NULL,  -- Imię i nazwisko pracownika.
                                  email VARCHAR(50) NOT NULL UNIQUE,-- Adres email, musi być unikalny.
                                  role_id BIGINT NULL,              -- ID roli biznesowej (klucz obcy). Może być puste.
                                  salary DECIMAL NOT NULL,          -- Wynagrodzenie.
                                  department_id BIGINT NULL         -- ID działu (klucz obcy). Może być puste.
);

-- Tworzy tabelę 'departments' do przechowywania nazw działów w firmie.
CREATE TABLE public.departments (
                                    department_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, -- Unikalny ID działu.
                                    department_name VARCHAR(50) UNIQUE NOT NULL -- Nazwa działu, musi być unikalna.
);

-- Tworzy tabelę 'business_roles' do przechowywania nazw ról/stanowisk biznesowych.
CREATE TABLE public.business_roles (
                                       role_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, -- Unikalny ID roli.
                                       role_name VARCHAR(50) UNIQUE NOT NULL -- Nazwa roli, musi być unikalna.
);

-- Tworzy tabelę 'attendances' do śledzenia obecności pracowników.
CREATE TABLE public.attendances (
                                    attendance_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, -- Unikalny ID rekordu obecności.
                                    employee_id BIGINT NOT NULL,      -- ID pracownika.
                                    date DATE NOT NULL                -- Data obecności.
);

-- Tworzy tabelę 'projects' do przechowywania informacji o projektach.
CREATE TABLE public.projects (
                                 project_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, -- Unikalny ID projektu.
                                 project_name VARCHAR(50) NOT NULL, -- Nazwa projektu.
                                 start_date DATE NOT NULL,         -- Data rozpoczęcia projektu.
                                 deadline_date DATE NULL           -- Ostateczny termin zakończenia projektu (może być pusty).
);

-- Tworzy tabelę łączącą 'employee_project' do przypisywania pracowników do projektów (relacja wiele-do-wielu).
CREATE TABLE public.employee_project (
                                         employee_id BIGINT NOT NULL,      -- ID pracownika.
                                         project_id BIGINT NOT NULL        -- ID projektu.
);

-- =================================================================
-- DEFINIOWANIE RELACJI (KLUCZE OBCE)
-- =================================================================

-- Dodaje klucz obcy do tabeli 'logs', łącząc 'user_id' z tabelą 'users'.
ALTER TABLE auditing.logs ADD CONSTRAINT fk_user FOREIGN KEY (user_id) REFERENCES app_security.users;

-- Dodaje klucz obcy do tabeli 'app_roles', łącząc 'user_id' z tabelą 'users'.
ALTER TABLE app_security.app_roles ADD CONSTRAINT fk_user FOREIGN KEY (user_id) REFERENCES app_security.users;

-- Dodaje klucz obcy do tabeli 'users', łącząc 'employee_id' z tabelą 'employees'.
ALTER TABLE app_security.users ADD CONSTRAINT fk_employee FOREIGN KEY (employee_id) REFERENCES public.employees;

-- Dodaje dwa klucze obce do tabeli 'employees'.
ALTER TABLE public.employees
    -- Łączy 'role_id' z tabelą 'business_roles'.
    ADD CONSTRAINT fk_role FOREIGN KEY (role_id) REFERENCES public.business_roles,
    -- Łączy 'department_id' z tabelą 'departments'.
    ADD CONSTRAINT fk_department FOREIGN KEY (department_id) REFERENCES public.departments;

-- =================================================================
-- WSTAWIANIE POCZĄTKOWYCH DANYCH
-- =================================================================

-- Wstawia nową rolę biznesową 'Administrator' do tabeli 'business_roles'.
INSERT INTO public.business_roles (role_name) VALUES ('Administrator');

-- Wstawia nowy dział 'Dział IT' do tabeli 'departments'.
INSERT INTO public.departments (department_name) VALUES ('Dział IT');

-- Wstawia nowego pracownika-administratora.
-- Dane 'role_id' i 'department_id' są pobierane dynamicznie z innych tabel na podstawie ich nazw.
INSERT INTO public.employees (full_name, email, role_id, salary, department_id)
SELECT 'Adam BitsTechWorld', 'admin@test.example', r.role_id, 100000, d.department_id FROM public.business_roles r, public.departments d
WHERE r.role_name = 'Administrator' AND d.department_name = 'Dział IT';

-- To jest złożone zapytanie (CTE - Common Table Expression).
-- 1. (WITH inserted_user AS ...) Wstawia nowego użytkownika do 'app_security.users' na podstawie emaila pracownika i zwraca jego nowo utworzone 'user_id'.
-- 2. (INSERT INTO app_security.app_roles ...) Używa zwróconego 'user_id' do wstawienia rekordu do 'app_roles', przypisując mu rolę bieżącego użytkownika bazy danych ('current_user').
WITH inserted_user AS (
    INSERT INTO app_security.users (employee_id, created_at, updated_at)
        SELECT employees.employee_id, NOW(), NOW() FROM public.employees WHERE email = 'admin@test.example'
        RETURNING user_id
)
INSERT INTO app_security.app_roles (user_id, app_role)
SELECT user_id, current_user FROM inserted_user;