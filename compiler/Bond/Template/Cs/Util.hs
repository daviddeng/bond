-- Copyright (c) Microsoft. All rights reserved.
-- Licensed under the MIT license. See LICENSE file in the project root for full license information.

{-# LANGUAGE QuasiQuotes, OverloadedStrings, RecordWildCards #-}

module Bond.Template.Cs.Util
    ( typeAttributes
    , propertyAttributes
    , schemaAttributes
    , paramConstraints
    , defaultValue
    , disableReSharperWarnings
    ) where

import Data.Monoid
import Text.Shakespeare.Text
import Bond.Version
import Bond.Schema
import Bond.Template.TypeMapping
import Bond.Template.Util

disableReSharperWarnings = [lt|
#region ReSharper warnings
// ReSharper disable PartialTypeWithSinglePart
// ReSharper disable RedundantNameQualifier
// ReSharper disable InconsistentNaming
// ReSharper disable CheckNamespace
// ReSharper disable UnusedParameter.Local
// ReSharper disable RedundantUsingDirective
#endregion
|]

-- C# field/property attributes
propertyAttributes cs Field {..} = 
    schemaAttributes 2 fieldAttributes
 <> [lt|[global::Bond.Id(#{fieldOrdinal})#{typeAttribute}#{modifierAttribute fieldType fieldModifier}]|]
        where
            csAnnotated = setTypeMapping cs csAnnotatedTypeMapping
            annotatedType = getTypeName csAnnotated fieldType
            propertyType = getTypeName cs fieldType
            typeAttribute = if annotatedType /= propertyType 
                then [lt|, global::Bond.Type(typeof(#{annotatedType}))|]
                else mempty
            modifierAttribute BT_MetaName _ = [lt|, global::Bond.RequiredOptional|]
            modifierAttribute BT_MetaFullName _ = [lt|, global::Bond.RequiredOptional|]
            modifierAttribute _ Required = [lt|, global::Bond.Required|]
            modifierAttribute _ RequiredOptional = [lt|, global::Bond.RequiredOptional|]
            modifierAttribute _ _ = mempty

-- C# class/struct/interface attributes
typeAttributes cs s@Struct {..} = 
    optionalTypeAttributes cs s
 <> [lt|[global::Bond.Schema]
    |]
 <> generatedCodeAttr

-- C# enum attributes
typeAttributes cs e@Enum {..} = 
    optionalTypeAttributes cs e
 <> generatedCodeAttr

generatedCodeAttr = [lt|[System.CodeDom.Compiler.GeneratedCode("gbc", "#{majorVersion}.#{minorVersion}")]|]

optionalTypeAttributes cs decl = 
    schemaAttributes 1 (declAttributes decl)
 <> namespaceAttribute
  where
    namespaceAttribute = if getIdlNamespace cs == getNamespace cs
        then mempty 
        else [lt|[global::Bond.Namespace("#{getIdlQualifiedName $ getIdlNamespace cs}")]
    |]

-- Attributes defined by the user in the schema
schemaAttributes indent = newlineSepEnd indent schemaAttribute
  where
    schemaAttribute Attribute {..} = 
        [lt|[global::Bond.Attribute("#{getIdlQualifiedName attrName}", "#{attrValue}")]|]

-- generic type parameter constraints
paramConstraints = newlineBeginSep 2 constraint
  where
    constraint (TypeParam _ Nothing) = mempty
    constraint (TypeParam name (Just Value)) = [lt|where #{name} : struct|]

-- Initial value for C# field/property or Nothing if C# implicit default is OK
defaultValue cs Field {fieldDefault = Nothing, ..} = implicitDefault fieldType
    where
        newInstance t = Just [lt|new #{getInstanceTypeName cs t}()|]
        implicitDefault BT_String = Just "string.Empty"
        implicitDefault BT_WString = Just "string.Empty"
        implicitDefault (BT_Bonded t) = Just [lt|global::Bond.Bonded<#{getTypeName cs t}>.Empty|]
        implicitDefault t@(BT_TypeParam _) = Just [lt|global::Bond.GenericFactory.Create<#{getInstanceTypeName cs t}>()|]
        implicitDefault t@(BT_List _) = newInstance t
        implicitDefault t@(BT_Vector _) = newInstance t
        implicitDefault t@(BT_Set _) = newInstance t
        implicitDefault t@(BT_Map _ _) = newInstance t
        implicitDefault t@BT_Blob = newInstance t
        implicitDefault t@(BT_UserDefined a@Alias {..} args) = 
            case findAliasMapping cs a of
                Nothing -> implicitDefault $ resolveAlias a args
                Just _ -> newInstance t
        implicitDefault t@(BT_UserDefined _ _) = newInstance t
        implicitDefault _ = Nothing

defaultValue cs Field {fieldDefault = (Just def), ..} = explicitDefault def
    where
        explicitDefault (DefaultInteger x) = Just [lt|#{x}|]
        explicitDefault (DefaultFloat x) = Just $ floatLiteral fieldType x
            where
                floatLiteral BT_Float x = [lt|#{x}F|]
                floatLiteral BT_Double x = [lt|#{x}|]
        explicitDefault (DefaultBool True) = Just "true"
        explicitDefault (DefaultBool False) = Just "false"
        explicitDefault (DefaultString x) = Just [lt|"#{x}"|]
        explicitDefault (DefaultEnum x) = Just [lt|#{getTypeName cs fieldType}.#{x}|]
        explicitDefault _ = Nothing
