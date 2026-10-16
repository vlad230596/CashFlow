"""MCC route registration with injected queries; does not import the app or ORM."""

from flask import Blueprint, g, jsonify, request


def create_mcc_blueprint(catalogue_handler, snapshot_loader, versioned_snapshot=None):
    blueprint = Blueprint("mcc", __name__)
    blueprint.add_url_rule("", "catalogue", catalogue_handler, methods=["GET"])

    @blueprint.get("/offline-snapshot")
    def offline_snapshot():
        try:
            schema = request.args.get('schema', '2')
            if schema not in ('2', '3'):
                raise ValueError('schema must be 2 or 3')
            if schema == '3':
                return versioned_snapshot(request.args.get('as_of'), g.auth_user.id)
            payload = snapshot_loader(request.args.get("as_of"))
        except ValueError as error:
            return jsonify({"error": str(error)}), 400
        return jsonify(payload)

    @blueprint.get('/offline-manifest')
    def offline_manifest():
        try:
            return versioned_snapshot(request.args.get('as_of'), g.auth_user.id, manifest_only=True)
        except ValueError as error:
            return jsonify({'error': str(error)}), 400

    return blueprint
