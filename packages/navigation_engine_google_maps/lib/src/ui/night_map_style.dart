/// A dark map style for night driving, as the JSON array of style rules that
/// `GoogleMap.style` takes (see [GoogleMapsNavigationView.style]).
///
/// Deep blue-grey ground (`#1b2230`), light grey labels (`#aab3c0`), roads
/// `#2b3343`, arterials `#323c4e`, highways `#4b5263`, water `#0f1b2c` and
/// transit `#252c39`; points-of-interest labels are hidden.
const String googleStyleNightMapStyle = '''
[
  {
    "featureType": "water",
    "elementType": "geometry",
    "stylers": [{"color": "#0f1b2c"}]
  },
  {
    "featureType": "water",
    "elementType": "labels.text.fill",
    "stylers": [{"color": "#56677d"}]
  },
  {
    "featureType": "landscape.natural",
    "elementType": "geometry",
    "stylers": [{"color": "#1e2a29"}]
  },
  {
    "elementType": "geometry",
    "stylers": [{"color": "#1b2230"}]
  },
  {
    "featureType": "administrative",
    "elementType": "geometry.stroke",
    "stylers": [{"color": "#3b4455"}]
  },
  {
    "featureType": "road",
    "elementType": "geometry",
    "stylers": [{"color": "#2b3343"}]
  },
  {
    "featureType": "road",
    "elementType": "geometry.stroke",
    "stylers": [{"color": "#141922"}]
  },
  {
    "featureType": "road.arterial",
    "elementType": "geometry",
    "stylers": [{"color": "#323c4e"}]
  },
  {
    "featureType": "road.highway",
    "elementType": "geometry",
    "stylers": [{"color": "#4b5263"}]
  },
  {
    "featureType": "road.highway",
    "elementType": "geometry.stroke",
    "stylers": [{"color": "#191e28"}]
  },
  {
    "featureType": "road",
    "elementType": "labels.text.fill",
    "stylers": [{"color": "#8e98a8"}]
  },
  {
    "featureType": "transit",
    "elementType": "geometry",
    "stylers": [{"color": "#252c39"}]
  },
  {
    "featureType": "transit.station",
    "elementType": "labels.text.fill",
    "stylers": [{"color": "#7d8797"}]
  },
  {
    "featureType": "poi",
    "elementType": "labels",
    "stylers": [{"visibility": "off"}]
  },
  {
    "featureType": "poi.park",
    "elementType": "geometry",
    "stylers": [{"color": "#1c2b24"}]
  },
  {
    "elementType": "labels.text.fill",
    "stylers": [{"color": "#aab3c0"}]
  },
  {
    "elementType": "labels.text.stroke",
    "stylers": [{"color": "#1b2230"}]
  }
]
''';
