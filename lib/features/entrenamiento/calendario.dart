import 'package:flutter/material.dart';
import 'training_service.dart';
import 'package:rms/shared/themes/feed_palette.dart';

enum VistaCalendario { mes, semana, dia }

class CalendarioPage extends StatefulWidget {
  const CalendarioPage({super.key});

  @override
  State<CalendarioPage> createState() => _CalendarioPageState();
}

class _CalendarioPageState extends State<CalendarioPage> {
  VistaCalendario _vistaActual = VistaCalendario.mes;
  DateTime _fechaSeleccionada = DateTime.now();
  int _semanaSeleccionada = 1;

  final Set<String> _completedDates = {};
  bool _isLoading = true;
  final TrainingService _trainingService = TrainingService();

  final List<String> _mesesNames = [
    'Enero',
    'Febrero',
    'Marzo',
    'Abril',
    'Mayo',
    'Junio',
    'Julio',
    'Agosto',
    'Septiembre',
    'Octubre',
    'Noviembre',
    'Diciembre',
  ];

  // Rango de años solicitado
  final List<int> _anios = List.generate(
    9,
    (index) => 2022 + index,
  ); // 2022 a 2030

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    final history = await _trainingService.getHistory();
    if (mounted) {
      setState(() {
        for (var item in history) {
          if (item['isCompleted'] == true) {
            String dateStr = item['date']; // Format: YYYY-MM-DD
            // Normalize potential ISO date
            if (dateStr.contains('T')) {
              dateStr = dateStr.split('T')[0];
            }
            _completedDates.add(dateStr);
          }
        }
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: FeedPalette.background,
        body: Center(child: CircularProgressIndicator(color: Colors.blue)),
      );
    }
    return Scaffold(
      backgroundColor: FeedPalette.background,
      appBar: AppBar(
        title: Text(
          'Calendario de Entrenamiento',
          style: TextStyle(color: FeedPalette.text, fontSize: 16),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: FeedPalette.text, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          _buildSelectorVistaSuperior(),
          _buildCabeceraFiltros(),
          Expanded(child: _renderizarCuerpo()),
        ],
      ),
    );
  }

  // --- SELECTOR SUPERIOR ---
  Widget _buildSelectorVistaSuperior() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0x1AFFFFFF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: VistaCalendario.values.map((v) {
          bool sel = _vistaActual == v;
          return GestureDetector(
            onTap: () => setState(() => _vistaActual = v),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: sel ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                v.name.toUpperCase(),
                style: TextStyle(
                  color: sel ? Colors.black : FeedPalette.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // --- CABECERA DE FILTROS DINÁMICA ---
  Widget _buildCabeceraFiltros() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
      child: Wrap(
        // Wrap permite que si no caben los 3 cuadros, bajen de línea suavemente
        spacing: 10,
        runSpacing: 10,
        alignment: WrapAlignment.center,
        children: [
          // Selector de Mes (Siempre visible)
          _botonSelectorFiltro(
            ancho: 120,
            label: _mesesNames[_fechaSeleccionada.month - 1],
            onTap: _abrirSelectorMeses,
          ),

          // Selector de Semana (Solo en vista SEMANA)
          if (_vistaActual == VistaCalendario.semana)
            _botonSelectorFiltro(
              ancho: 110,
              label: "Sem. $_semanaSeleccionada",
              onTap: _mostrarSelectorSemanas,
            ),

          // Selector de Año (Visible en todas las pestañas)
          _botonSelectorFiltro(
            ancho: 90,
            label: "${_fechaSeleccionada.year}",
            onTap: _abrirSelectorAnios,
          ),
        ],
      ),
    );
  }

  Widget _botonSelectorFiltro({
    required double ancho,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: ancho,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: const Color(0x1A2196F3),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0x332196F3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                color: FeedPalette.text,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Icon(Icons.keyboard_arrow_down, color: Colors.blue, size: 18),
          ],
        ),
      ),
    );
  }

  // --- SELECTORES (BOTTOM SHEETS) ---
  void _abrirSelectorAnios() {
    showModalBottomSheet(
      context: context,
      backgroundColor: FeedPalette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => ListView(
        shrinkWrap: true,
        children: _anios
            .map(
              (anio) => ListTile(
                title: Text(
                  "$anio",
                  style: TextStyle(color: FeedPalette.text),
                  textAlign: TextAlign.center,
                ),
                onTap: () {
                  setState(
                    () => _fechaSeleccionada = DateTime(
                      anio,
                      _fechaSeleccionada.month,
                      1,
                    ),
                  );
                  Navigator.pop(context);
                },
              ),
            )
            .toList(),
      ),
    );
  }

  void _abrirSelectorMeses() {
    showModalBottomSheet(
      context: context,
      backgroundColor: FeedPalette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => ListView.builder(
        itemCount: 12,
        itemBuilder: (context, i) => ListTile(
          title:
              Text(_mesesNames[i], style: TextStyle(color: FeedPalette.text)),
          onTap: () {
            setState(() {
              _fechaSeleccionada = DateTime(_fechaSeleccionada.year, i + 1, 1);
              _semanaSeleccionada = 1;
            });
            Navigator.pop(context);
          },
        ),
      ),
    );
  }

  void _mostrarSelectorSemanas() {
    int totalDias = DateTime(
      _fechaSeleccionada.year,
      _fechaSeleccionada.month + 1,
      0,
    ).day;
    int numSemanas = (totalDias / 7).ceil();

    showModalBottomSheet(
      context: context,
      backgroundColor: FeedPalette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => ListView.builder(
        shrinkWrap: true,
        itemCount: numSemanas,
        itemBuilder: (context, i) => ListTile(
          title: Text("Semana ${i + 1}",
              style: TextStyle(color: FeedPalette.text)),
          onTap: () {
            setState(() => _semanaSeleccionada = i + 1);
            Navigator.pop(context);
          },
        ),
      ),
    );
  }

  // --- RENDERIZADO CUERPO ---
  Widget _renderizarCuerpo() {
    switch (_vistaActual) {
      case VistaCalendario.mes:
        return _vistaMes();
      case VistaCalendario.semana:
        return _vistaSemana();
      case VistaCalendario.dia:
        return _vistaDiaLista();
    }
  }

  // VISTA MES
  Widget _vistaMes() {
    final int diasEnMes = DateTime(
      _fechaSeleccionada.year,
      _fechaSeleccionada.month + 1,
      0,
    ).day;
    final int primerDia =
        DateTime(_fechaSeleccionada.year, _fechaSeleccionada.month, 1).weekday -
            1;

    return GridView.builder(
      padding: const EdgeInsets.all(20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.8,
      ),
      itemCount: (diasEnMes + (primerDia > 0 ? primerDia : 0)).clamp(0, 42),
      itemBuilder: (context, index) {
        if (index < primerDia) return const SizedBox();
        int dia = index - primerDia + 1;
        if (dia > diasEnMes) return const SizedBox();
        String kMonth = _fechaSeleccionada.month.toString().padLeft(2, '0');
        String kDay = dia.toString().padLeft(2, '0');
        String key = "${_fechaSeleccionada.year}-$kMonth-$kDay";
        bool isCompleted = _completedDates.contains(key);

        bool esHoy = DateTime.now().day == dia &&
            DateTime.now().month == _fechaSeleccionada.month &&
            DateTime.now().year == _fechaSeleccionada.year;

        return GestureDetector(
          onTap: () => _mostrarDetallePopup(dia, isCompleted, key),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0x0DFFFFFF),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: esHoy
                    ? FeedPalette.accent
                    : (isCompleted
                        ? Colors.green.withAlpha(200)
                        : const Color(0x1AFFFFFF)),
                width: esHoy ? 2 : 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  "$dia",
                  style: TextStyle(
                    color: isCompleted
                        ? Colors.greenAccent
                        : (esHoy ? FeedPalette.accent : FeedPalette.text),
                    fontWeight: isCompleted || esHoy
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
                if (isCompleted)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: _punto(Colors.greenAccent),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // VISTA SEMANA
  Widget _vistaSemana() {
    int diaInicio = (_semanaSeleccionada - 1) * 7 + 1;
    int diasEnMes = DateTime(
      _fechaSeleccionada.year,
      _fechaSeleccionada.month + 1,
      0,
    ).day;

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      itemCount: 7,
      itemBuilder: (context, i) {
        int diaActual = diaInicio + i;
        if (diaActual > diasEnMes) return const SizedBox();
        String kMonth = _fechaSeleccionada.month.toString().padLeft(2, '0');
        String kDay = diaActual.toString().padLeft(2, '0');
        String k = "${_fechaSeleccionada.year}-$kMonth-$kDay";
        bool isCompleted = _completedDates.contains(k);

        bool esHoy = DateTime.now().day == diaActual &&
            DateTime.now().month == _fechaSeleccionada.month &&
            DateTime.now().year == _fechaSeleccionada.year;

        return ListTile(
          leading: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(
                color: isCompleted
                    ? Colors.green
                    : (esHoy ? FeedPalette.accent : Colors.transparent),
              ),
              borderRadius: BorderRadius.circular(8),
              color: isCompleted
                  ? Colors.green.withAlpha(40)
                  : const Color(0x0DFFFFFF),
            ),
            child: Text(
              "$diaActual",
              style: TextStyle(
                color: isCompleted ? Colors.greenAccent : FeedPalette.text,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          title: Text(
            "${_mesesNames[_fechaSeleccionada.month - 1]} ${_fechaSeleccionada.year}",
            style: TextStyle(color: FeedPalette.muted, fontSize: 13),
          ),
          trailing: Icon(
            isCompleted ? Icons.check_circle : Icons.radio_button_unchecked,
            color: isCompleted ? Colors.greenAccent : FeedPalette.muted,
            size: 18,
          ),
          onTap: () => _mostrarDetallePopup(diaActual, isCompleted, k),
        );
      },
    );
  }

  // VISTA DÍA
  Widget _vistaDiaLista() {
    final int diasEnMes = DateTime(
      _fechaSeleccionada.year,
      _fechaSeleccionada.month + 1,
      0,
    ).day;

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      itemCount: diasEnMes,
      itemBuilder: (context, i) {
        int diaActual = i + 1;
        String kMonth = _fechaSeleccionada.month.toString().padLeft(2, '0');
        String kDay = diaActual.toString().padLeft(2, '0');
        String k = "${_fechaSeleccionada.year}-$kMonth-$kDay";
        bool isCompleted = _completedDates.contains(k);

        bool esHoy = DateTime.now().day == diaActual &&
            DateTime.now().month == _fechaSeleccionada.month &&
            DateTime.now().year == _fechaSeleccionada.year;

        return Card(
          color: isCompleted
              ? Colors.green.withAlpha(20)
              : const Color(0x12FFFFFF),
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: isCompleted
                  ? Colors.green.withAlpha(100)
                  : (esHoy ? FeedPalette.accent : Colors.transparent),
              width: 1,
            ),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isCompleted
                  ? Colors.green.withAlpha(40)
                  : const Color(0x1A2196F3),
              child: Text(
                "$diaActual",
                style: TextStyle(
                  color: isCompleted ? Colors.greenAccent : Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(
              "${_mesesNames[_fechaSeleccionada.month - 1]} $diaActual, ${_fechaSeleccionada.year}",
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
            subtitle: Text(
              isCompleted ? "Entrenamiento Completado" : "Sin registrar",
              style: TextStyle(
                color: isCompleted ? Colors.greenAccent : Colors.white24,
                fontSize: 11,
              ),
            ),
            trailing: Icon(
              isCompleted ? Icons.check_circle : Icons.arrow_forward_ios,
              color: isCompleted ? Colors.greenAccent : Colors.white24,
              size: 18,
            ),
            onTap: () => _mostrarDetallePopup(diaActual, isCompleted, k),
          ),
        );
      },
    );
  }

  // --- DIÁLOGOS ---
  void _mostrarDetallePopup(int dia, bool isCompleted, String key) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: FeedPalette.surface,
        title: Text(
          "Día $dia de ${_mesesNames[_fechaSeleccionada.month - 1]}",
          style: TextStyle(color: FeedPalette.text),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _filaPopup(
              "Estado",
              isCompleted ? "Completado" : "Pendiente",
              isCompleted ? Colors.greenAccent : Colors.redAccent,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("CERRAR"),
          ),
        ],
      ),
    );
  }

  Widget _filaPopup(String t, String v, Color c) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(t, style: TextStyle(color: c)),
            Text(v, style: TextStyle(color: Colors.white)),
          ],
        ),
      );

  Widget _punto(Color c) => Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      );
}
