/// navigation_engine views on Google Maps (google_maps_flutter), and Google
/// routing (Routes API v2) and place search (Places API (New) and the
/// Geocoding API).
///
/// Google Maps Platform's terms ask that the routing and search results be
/// shown on a Google map, such as this package's (see the README).
library;

export 'package:navigation_engine/navigation_engine.dart'
    show GeoPoint, NavigationSession;
export 'package:navigation_engine_flutter/navigation_engine_flutter.dart'
    show
        AlongRouteCategory,
        AlongRoutePlace,
        AlongRouteQuery,
        AlongRouteSearch,
        AlternateRoute,
        AlternateRoutesMap,
        AudioGuidance,
        CarPuck,
        DestinationPinMap,
        GoogleStyleArrivalSheet,
        GoogleStyleColors,
        GoogleStyleCompassButton,
        GoogleStyleControlStack,
        GoogleStyleIncidentType,
        GoogleStyleLaneGuidance,
        GoogleStyleManeuverHeader,
        GoogleStyleOverviewPanel,
        GoogleStyleRecenterButton,
        GoogleStyleReportButton,
        GoogleStyleReportSheet,
        GoogleStyleRoundButton,
        GoogleStyleRouteLabelColors,
        GoogleStyleSearchAlongRoute,
        GoogleStyleSheetAction,
        GoogleStyleSoundButton,
        GoogleStyleSpeedCluster,
        GoogleStyleStepList,
        GoogleStyleTripProgressBar,
        GoogleStyleTripSheet,
        IncidentType,
        NavigationFlowController,
        NavigationStrings,
        PlaceLabel,
        RouteColors,
        RouteLabelColors,
        SearchPinsMap,
        SpeedLimitSignStyle,
        SpeedingLevel,
        VehicleImageBuilder,
        fitCameraToBounds,
        laneDirectionIcon,
        paintDestinationPin,
        paintRouteLabel,
        paintSearchPin,
        showGoogleStyleReportSheet;

export 'src/google_maps_navigation_map.dart'
    hide
        dispatchMapTap,
        routePolylines,
        toCameraPosition,
        toLatLng,
        vehicleIconFrom;
export 'src/google_maps_navigation_view.dart';
export 'src/routing/google_routes_route_provider.dart';
export 'src/search/google_places_search.dart';
export 'src/ui/google_style_navigation.dart';
export 'src/ui/night_map_style.dart';
export 'src/web_service/google_routes_exception.dart';
