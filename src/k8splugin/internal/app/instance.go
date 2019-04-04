/*
 * Copyright 2018 Intel Corporation, Inc
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package app

import (
	"encoding/base64"
	"encoding/json"
	"math/rand"
	"os"

	"k8splugin/internal/db"
	"k8splugin/internal/rb"

	pkgerrors "github.com/pkg/errors"
)

// InstanceRequest contains the parameters needed for instantiation
// of profiles
type InstanceRequest struct {
	RBName      string            `json:"rb-name"`
	RBVersion   string            `json:"rb-version"`
	ProfileName string            `json:"profile-name"`
	CloudRegion string            `json:"cloud-region"`
	Labels      map[string]string `json:"labels"`
}

// InstanceResponse contains the response from instantiation
type InstanceResponse struct {
	ID          string              `json:"id"`
	RBName      string              `json:"rb-name"`
	RBVersion   string              `json:"rb-version"`
	ProfileName string              `json:"profile-name"`
	CloudRegion string              `json:"cloud-region"`
	Namespace   string              `json:"namespace"`
	Resources   map[string][]string `json:"resources"`
}

// InstanceManager is an interface exposes the instantiation functionality
type InstanceManager interface {
	Create(i InstanceRequest) (InstanceResponse, error)
	Get(id string) (InstanceResponse, error)
	Delete(id string) error
}

// InstanceKey is used as the primary key in the db
type InstanceKey struct {
	ID string `json:"id"`
}

// We will use json marshalling to convert to string to
// preserve the underlying structure.
func (dk InstanceKey) String() string {
	out, err := json.Marshal(dk)
	if err != nil {
		return ""
	}

	return string(out)
}

// InstanceClient implements the InstanceManager interface
// It will also be used to maintain some localized state
type InstanceClient struct {
	storeName string
	tagInst   string
}

// Using 6 bytes of randomness to generate an 8 character string
func generateInstanceID() string {
	b := make([]byte, 6)
	rand.Read(b)
	return base64.URLEncoding.EncodeToString(b)
}

// NewInstanceClient returns an instance of the InstanceClient
// which implements the InstanceManager
func NewInstanceClient() *InstanceClient {
	return &InstanceClient{
		storeName: "rbdef",
		tagInst:   "instance",
	}
}

// Create an entry for the resource bundle profile in the database
func (v *InstanceClient) Create(i InstanceRequest) (InstanceResponse, error) {

	// Name is required
	if i.RBName == "" || i.RBVersion == "" || i.ProfileName == "" || i.CloudRegion == "" {
		return InstanceResponse{},
			pkgerrors.New("RBName, RBversion, ProfileName, CloudRegion are required to create a new instance")
	}

	//Check if profile exists
	profile, err := rb.NewProfileClient().Get(i.RBName, i.RBVersion, i.ProfileName)
	if err != nil {
		return InstanceResponse{}, pkgerrors.New("Unable to find Profile to create instance")
	}

	overrideValues := []string{}

	//Execute the kubernetes create command
	resMap, err := rb.NewProfileClient().Resolve(i.RBName, i.RBVersion, i.ProfileName, overrideValues)
	if err != nil {
		return InstanceResponse{}, pkgerrors.Wrap(err, "Error resolving helm charts")
	}

	k8sClient := kubernetesClient{}
	err = k8sClient.init(os.Getenv("KUBE_CONFIG_DIR") + "/" + i.CloudRegion)
	if err != nil {
		return InstanceResponse{}, pkgerrors.Wrap(err, "Getting CloudRegion Information")
	}

	createdResources, err := k8sClient.createResources(resMap, profile.Namespace)
	if err != nil {
		return InstanceResponse{}, pkgerrors.Wrap(err, "Create Kubernetes Resources")
	}

	id := generateInstanceID()

	//Compose the return response
	resp := InstanceResponse{
		ID:          id,
		RBName:      i.RBName,
		RBVersion:   i.RBVersion,
		ProfileName: i.ProfileName,
		CloudRegion: i.CloudRegion,
		Namespace:   profile.Namespace,
		Resources:   createdResources,
	}

	key := InstanceKey{
		ID: id,
	}
	err = db.DBconn.Create(v.storeName, key, v.tagInst, resp)
	if err != nil {
		return InstanceResponse{}, pkgerrors.Wrap(err, "Creating Instance DB Entry")
	}

	return resp, nil
}

// Get returns the instance for corresponding ID
func (v *InstanceClient) Get(id string) (InstanceResponse, error) {
	key := InstanceKey{
		ID: id,
	}
	value, err := db.DBconn.Read(v.storeName, key, v.tagInst)
	if err != nil {
		return InstanceResponse{}, pkgerrors.Wrap(err, "Get Instance")
	}

	//value is a byte array
	if value != nil {
		resp := InstanceResponse{}
		err = db.DBconn.Unmarshal(value, &resp)
		if err != nil {
			return InstanceResponse{}, pkgerrors.Wrap(err, "Unmarshaling Instance Value")
		}
		return resp, nil
	}

	return InstanceResponse{}, pkgerrors.New("Error getting Instance")
}

// Delete the Instance from database
func (v *InstanceClient) Delete(id string) error {
	inst, err := v.Get(id)
	if err != nil {
		return pkgerrors.Wrap(err, "Error getting Instance")
	}

	k8sClient := kubernetesClient{}
	err = k8sClient.init(os.Getenv("KUBE_CONFIG_DIR") + "/" + inst.CloudRegion)
	if err != nil {
		return pkgerrors.Wrap(err, "Getting CloudRegion Information")
	}

	err = k8sClient.deleteResources(inst.Resources, inst.Namespace)
	if err != nil {
		return pkgerrors.Wrap(err, "Deleting Instance Resources")
	}

	key := InstanceKey{
		ID: id,
	}
	err = db.DBconn.Delete(v.storeName, key, v.tagInst)
	if err != nil {
		return pkgerrors.Wrap(err, "Delete Instance")
	}

	return nil
}