import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_map/plugin_api.dart';
import 'package:user_location/src/user_location_marker.dart';
import 'package:user_location/src/user_location_options.dart';
import 'package:latlong/latlong.dart';
import 'package:geolocation/geolocation.dart';
import 'dart:async';
import 'dart:math' as math;
import "dart:math" show pi;

class MapsPluginLayer extends StatefulWidget {
  final UserLocationOptions options;
  final MapState map;
  final Stream<Null> stream;

  MapsPluginLayer(this.options, this.map, this.stream);

  @override
  _MapsPluginLayerState createState() => _MapsPluginLayerState();
}

class _MapsPluginLayerState extends State<MapsPluginLayer>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  LatLng _currentLocation;
  UserLocationMarker _locationMarker;
  EventChannel _stream = EventChannel('locationStatusStream');

  bool mapLoaded;
  bool initialStateOfupdateMapLocationOnPositionChange;
  bool _locationStatusChanged;

  double _direction;

  StreamSubscription<LocationResult> _onLocationChangedStreamSubscription;
  StreamSubscription<CompassEvent> _compassStreamSubscription;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    printLog("AppLifecycleState changed, new state: $state");
    if (state == AppLifecycleState.resumed) {
      _subscribeToLocationChanges();
      _handleCompassDirection();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.paused) {
      _cancel(_onLocationChangedStreamSubscription);
      _cancel(_compassStreamSubscription);
    }
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    initialStateOfupdateMapLocationOnPositionChange =
        widget.options.updateMapLocationOnPositionChange;

    setState(() {
      mapLoaded = false;
    });
    initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancel(_onLocationChangedStreamSubscription);
    _cancel(_compassStreamSubscription);
    super.dispose();
  }

  Future<void> _cancel(StreamSubscription streamSubscription) async {
    if (streamSubscription != null) {
      await streamSubscription.cancel();
    }
  }

  void initialize() {
    Geolocation.isLocationOperational(
        permission: const LocationPermission(
      android: LocationPermissionAndroid.fine,
      ios: LocationPermissionIOS.always,
    )).then((status) async {
      if (status.isSuccessful) {
        _subscribeToLocationChanges();
      } else {
        await Geolocation.enableLocationServices();
        Geolocation.requestLocationPermission(
          permission: const LocationPermission(
            android: LocationPermissionAndroid.fine,
            ios: LocationPermissionIOS.always,
          ),
          openSettingsIfDenied: true,
        ).then((status) {
          if (status.isSuccessful) {
            _subscribeToLocationChanges();
          }
        });
      }
    });
    _handleCompassDirection();
  }

  void printLog(String log) {
    if (widget.options.verbose) {
      print(log);
    }
  }

  Future<void> _subscribeToLocationChanges() async {
    printLog("OnSubscribe to location change");

    await _cancel(_onLocationChangedStreamSubscription);

    final locationStatus = await Geolocation.isLocationOperational();
    if (locationStatus.isSuccessful) {
      _onLocationChangedStreamSubscription = Geolocation.locationUpdates(
              accuracy: LocationAccuracy.best, inBackground: false)
          .listen((result) {
        _addsMarkerLocationToMarkerLocationStream(result.location);
        setState(() {
          if (result.location.latitude == null ||
              result.location.longitude == null) {
            _currentLocation = LatLng(0, 0);
          } else {
            _currentLocation =
                LatLng(result.location.latitude, result.location.longitude);
          }

          /*var height = 20.0 * (1 - (result.location.accuracy / 100));
          var width = 20.0 * (1 - (result.location.accuracy / 100));
          if (height < 0 || width < 0) {
            height = 20;
            width = 20;
          }*/

          if (_locationMarker != null) {
            widget.options.markers.remove(_locationMarker);
          }
          //widget.options.markers.clear();

          printLog("Direction : " + (_direction ?? 0).toString());

          _locationMarker = UserLocationMarker(
              height: 60.0,
              width: 60.0,
              point:
                  LatLng(_currentLocation.latitude, _currentLocation.longitude),
              builder: (context) {
                return IgnorePointer(
                  child: Column(
                    children: <Widget>[
                      Stack(
                        alignment: AlignmentDirectional.center,
                        children: <Widget>[
                          (_direction == null)
                              ? SizedBox()
                              : ClipOval(
                                  child: Container(
                                    child: new Transform.rotate(
                                        angle: ((_direction ?? 0) *
                                                (math.pi / 180) *
                                                -2) +
                                            180,
                                        child: Container(
                                          child: CustomPaint(
                                            size: Size(60.0, 60.0),
                                            painter: MyDirectionPainter(),
                                          ),
                                        )),
                                  ),
                                ),
                          Container(
                            height: 20.0,
                            width: 20.0,
                            decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.blue[300].withOpacity(0.7)),
                          ),
                          widget.options.markerWidget ??
                              Container(
                                height: 10,
                                width: 10,
                                decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.blueAccent),
                              ),
                        ],
                      ),
                    ],
                  ),
                );
              });

          widget.options.markers.add(_locationMarker);

          if (widget.options.updateMapLocationOnPositionChange &&
              widget.options.mapController != null) {
            _moveMapToCurrentLocation();
          } else if (widget.options.updateMapLocationOnPositionChange) {
            if (!widget.options.updateMapLocationOnPositionChange) {
              widget.map.fitBounds(widget.map.bounds, FitBoundsOptions());
            }
            printLog(
                "Warning: updateMapLocationOnPositionChange set to true, but no mapController provided: can't move map");
          } else {
            forceMapUpdate();
          }

          if (widget.options.zoomToCurrentLocationOnLoad && (!mapLoaded)) {
            setState(() {
              mapLoaded = true;
            });
            animatedMapMove(
                _currentLocation, 17, widget.options.mapController, this);
          }
        });
      });
    }
  }

  void _moveMapToCurrentLocation({double zoom}) {
    if (_currentLocation != null) {
      animatedMapMove(
          LatLng(_currentLocation.latitude ?? LatLng(0, 0),
              _currentLocation.longitude ?? LatLng(0, 0)),
          zoom ?? widget.map.zoom ?? 15,
          widget.options.mapController,
          this);
    }
  }

  void _handleCompassDirection() {
    _compassStreamSubscription =
        FlutterCompass.events.listen((CompassEvent event) {
      setState(() {
        _direction = event.heading;
      });
      forceMapUpdate();
    });
  }

  _addsMarkerLocationToMarkerLocationStream(Location onValue) {
    if (widget.options.onLocationUpdate == null) {
      printLog("Stream not provided");
    } else {
      widget.options
          .onLocationUpdate(LatLng(onValue.latitude, onValue.longitude));
    }
  }

  Widget build(BuildContext context) {
    if (_locationMarker != null &&
        !widget.options.markers.contains(_locationMarker)) {
      widget.options.markers.add(_locationMarker);
    }

    return widget.options.showMoveToCurrentLocationFloatingActionButton
        ? Positioned(
            bottom: widget.options.fabBottom,
            right: widget.options.fabRight,
            height: widget.options.fabHeight,
            width: widget.options.fabWidth,
            child: InkWell(
                hoverColor: Colors.blueAccent[200],
                onTap: () {
                  if (initialStateOfupdateMapLocationOnPositionChange) {
                    setState(() {
                      widget.options.updateMapLocationOnPositionChange = false;
                    });
                  }
                  _moveMapToCurrentLocation(zoom: 17.0);
                },
                child: widget.options
                            .moveToCurrentLocationFloatingActionButton ==
                        null
                    ? Container(
                        decoration: BoxDecoration(
                            color: Colors.blueAccent,
                            borderRadius: BorderRadius.circular(20.0),
                            boxShadow: [
                              BoxShadow(color: Colors.grey, blurRadius: 10.0)
                            ]),
                        child: Icon(
                          Icons.my_location,
                          color: Colors.white,
                        ),
                      )
                    : widget.options.moveToCurrentLocationFloatingActionButton),
          )
        : Container();
  }

  void animatedMapMove(
      LatLng destLocation, double destZoom, _mapController, vsync) {
    // Create some tweens. These serve to split up the transition from one location to another.
    // In our case, we want to split the transition be<tween> our current map center and the destination.
    final _latTween = Tween<double>(
        begin: _mapController.center.latitude, end: destLocation.latitude);
    final _lngTween = Tween<double>(
        begin: _mapController.center.longitude, end: destLocation.longitude);
    final _zoomTween = Tween<double>(begin: _mapController.zoom, end: destZoom);

    // Create a animation controller that has a duration and a TickerProvider.
    var controller = AnimationController(
        duration: const Duration(milliseconds: 500), vsync: vsync);
    // The animation determines what path the animation will take. You can try different Curves values, although I found
    // fastOutSlowIn to be my favorite.
    Animation<double> animation =
        CurvedAnimation(parent: controller, curve: Curves.fastOutSlowIn);

    controller.addListener(() {
      _mapController.move(
          LatLng(_latTween.evaluate(animation), _lngTween.evaluate(animation)),
          _zoomTween.evaluate(animation));
    });

    animation.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        if (initialStateOfupdateMapLocationOnPositionChange) {
          setState(() {
            widget.options.updateMapLocationOnPositionChange = true;
          });
        }

        controller.dispose();
      } else if (status == AnimationStatus.dismissed) {
        if (initialStateOfupdateMapLocationOnPositionChange) {
          setState(() {
            widget.options.updateMapLocationOnPositionChange = true;
          });
        }
        controller.dispose();
      }
    });
    controller.forward();
  }

  void forceMapUpdate() {
    var zoom = widget.options.mapController.zoom;
    widget.options.mapController.move(widget.options.mapController.center,
        widget.options.mapController.zoom + 0.000001);
    widget.options.mapController
        .move(widget.options.mapController.center, zoom);
  }
}

class MyDirectionPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // create a bounding square, based on the centre and radius of the arc
    Rect rect = Rect.fromCircle(
      center: Offset(30.0, 30.0),
      radius: 40.0,
    );

    // a fancy rainbow gradient
    final Gradient gradient = RadialGradient(
      colors: <Color>[
        Colors.blue.shade500.withOpacity(0.6),
        Colors.blue.shade500.withOpacity(0.3),
        Colors.blue.shade500.withOpacity(0.1),
      ],
      stops: [
        0.0,
        0.5,
        1.0,
      ],
    );

    // create the Shader from the gradient and the bounding square
    final Paint paint = Paint()..shader = gradient.createShader(rect);

    // and draw an arc
    canvas.drawArc(rect, pi / 5, pi * 3 / 5, true, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    return false;
  }
}
