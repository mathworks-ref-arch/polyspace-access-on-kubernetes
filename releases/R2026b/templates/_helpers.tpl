{{- define "ingress.url" -}}
{{- if .Values.global.ingress.url -}}
{{ .Values.global.ingress.url }}
{{- else -}}
https://{{ .Values.global.ingress.host }}
{{- end -}}
{{- end -}}


{{- define "debug" -}}
{{ if .Values.global.debug }}"1"{{ else }}"0"{{ end }}
{{- end -}}


{{- define "usermanager.db.external" -}}
{{ if and .Values.usermanager.db.external .Values.usermanager.db.external.enabled }}true{{ else }}false{{ end }}
{{- end -}}

{{- define "polyspaceAccess.db.external" -}}
{{ if and .Values.polyspaceAccess.db.external .Values.polyspaceAccess.db.external.enabled }}true{{ else }}false{{ end }}
{{- end -}}


{{- define "polyspaceAccess.db.password" -}}
{{- if eq (include "polyspaceAccess.db.external" .) "true" -}}
valueFrom:
  secretKeyRef:
    name: {{ .Values.polyspaceAccess.db.external.passwordSecret.name }}
    key: {{ .Values.polyspaceAccess.db.external.passwordSecret.key }}
{{- else -}}
{{- if .Values.polyspaceAccess.db.passwordSecret -}}
valueFrom:
  secretKeyRef:
    name: {{ .Values.polyspaceAccess.db.passwordSecret.name }}
    key: {{ .Values.polyspaceAccess.db.passwordSecret.key }}
{{- else -}}
value: {{ .Values.polyspaceAccess.db.passwordString }}
{{- end -}}
{{- end -}}
{{- end -}}


{{- define "usermanager.authnz.samlAttributeToAuthnzMap" -}}
{{- if .Values.usermanager.server.config.saml.user -}}
{{- $map := dict
    "displayName" .Values.usermanager.server.config.saml.user.displayName
    "subjectId" .Values.usermanager.server.config.saml.user.id
    "extra" (dict
        "uid" .Values.usermanager.server.config.saml.user.id
        "email" .Values.usermanager.server.config.saml.user.email
        "image" .Values.usermanager.server.config.saml.user.image
    )
}}
{{- toJson $map -}}
{{- end -}}
{{- end -}}


{{- define "usermanager.authnz.ldapAttributeToAuthnzMap" -}}
{{- $ldap := index .Values.usermanager.server.config.providers 0 -}}
{{- $schema :=  $ldap.properties.searchOptions.user.schema -}}
{{- $map := dict
    "displayName" $schema.displayName
    "subjectId" $schema.id
    "extra" (dict
        "email" $schema.email
        "image" $schema.image
    )
}}
{{- toJson $map -}}
{{- end -}}

{{- define "usermanager.authnz.ldapIdentityConfig" -}}
{{- $ldap := index .Values.usermanager.server.config.providers 0 -}}
{{- $userValues :=  $ldap.properties.searchOptions.user -}}
{{- $groupValues :=  $ldap.properties.searchOptions.group -}}

{{- $user := dict
    "type" "user"
    "basedn" $userValues.searchBaseDN
    "filter"  (printf "(&(%s))" $userValues.filter)
    "schema" $userValues.schema
-}}

{{- $identityConfig := list $user -}}

{{- if $groupValues.enabled -}}
  {{- $group := dict
      "type" "group"
      "basedn" $groupValues.searchBaseDN
      "filter"  (printf "(&(%s))" $groupValues.filter)
      "schema" $groupValues.schema
  -}}
  {{- $identityConfig = append $identityConfig $group -}}
{{- end -}}

{{- toJson $identityConfig -}}
{{- end -}}


{{- define "usermanager.server.ldap.port" -}}
{{- $host := index . "host" -}}
{{- if contains ":" $host -}}
  {{ last (splitList ":" $host) }}
{{- end -}}
{{- end -}}


{{- define "usermanager.server.authn.type" -}}
{{- if .Values.usermanager.server.config.saml.enabled -}}
saml
{{- else if .Values.usermanager.server.config.providers -}}
ldap
{{- else -}}
internal
{{- end -}}
{{- end -}}


{{- define "usermanager.server.config" -}}
{{- $authType := include "usermanager.server.authn.type" . -}}

{{- $config := .Values.usermanager.server.config | merge (dict "authn" (dict "type" $authType)) -}}
{{- $config = $config | merge (dict "authnz" (dict "idpId" $authType)) -}}
{{- $config | toJson | quote -}}
{{- end -}}


{{- define "usermanager.authnz.idps" -}}
{{- $saml := "" -}}
{{- $ldap := "" -}}

{{- if .Values.usermanager.server.config.saml.enabled -}}
  {{- $saml = "saml|saml|authnz/saml/saml," -}}
{{- end -}}

{{- if .Values.usermanager.server.config.providers -}}
  {{- $ldap = "fallback|FallBack|authnz/fallback/fallback,ldap|ldap|authnz/ldap/ldap," -}}
{{- end -}}

{{- printf "%s%s%s" $saml $ldap "um|Usermanager|authnz/um/um" -}}
{{- end -}}
