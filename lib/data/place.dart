// lib/data/place.dart
import 'dart:convert';

class Place {
  final String id;
  final String name;
  final String? address;
  final String? detailedAddress;
  final double lat;
  final double lon;

  Place({
    required this.id,
    required this.name,
    this.address,
    this.detailedAddress,
    required this.lat,
    required this.lon,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'address': address,
        'detailedAddress': detailedAddress,
        'lat': lat,
        'lon': lon,
      };

  factory Place.fromJson(Map<String, dynamic> json) => Place(
        id: json['id'],
        name: json['name'],
        address: json['address'],
        detailedAddress: json['detailedAddress'],
        lat: json['lat'],
        lon: json['lon'],
      );
}
