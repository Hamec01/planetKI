@echo off
setlocal
cd /d "%~dp0"

set PY_CMD=
where python >nul 2>nul
if %errorlevel%==0 set PY_CMD=python
if not defined PY_CMD (
    where py >nul 2>nul
    if %errorlevel%==0 set PY_CMD=py -3
)
if not defined PY_CMD (
    echo Python не найден в PATH. Установи Python 3 ^(python.org^) и попробуй снова.
    pause
    goto :eof
)

%PY_CMD% -c "import PIL, numpy, tkinter" >nul 2>nul
if not %errorlevel%==0 (
    echo Ставлю недостающие зависимости ^(Pillow, numpy^)...
    %PY_CMD% -m pip install --quiet Pillow numpy
    if not %errorlevel%==0 (
        echo Не удалось установить зависимости. Проверь подключение к интернету или поставь их вручную:
        echo     pip install Pillow numpy
        pause
        goto :eof
    )
)

%PY_CMD% sprite_slicer_app.py
if not %errorlevel%==0 (
    echo.
    echo Приложение завершилось с ошибкой ^(код %errorlevel%^).
    pause
)
